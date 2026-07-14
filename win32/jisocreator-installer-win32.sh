#!/bin/bash

# =========================================================
# VALIDACIÓN DE ARGUMENTOS
# =========================================================
if [ "$#" -lt 1 ]; then
    echo "Uso: $0 <VERSION> [URL_CUSTOM]"
    echo "Ejemplo: $0 0.2.0"
    echo "Ejemplo con URL: $0 0.2.0 https://mi-dominio.com/jisocreator.zip"
    exit 1
fi

VERSION=$1
APP_NAME="jisocreator"
ORIGINAL_DIR=$(pwd)

# Permite pasar una URL personalizada como segundo argumento.
# Si no se pasa, construye la URL de los Releases de GitHub automáticamente.
# Ajusta "windows.zip" según cómo se llame el artefacto que subes a GitHub.
DEFAULT_URL=https://github.com/Cavallinux/jisocreator/releases/download/v${VERSION}/jisocreator-${VERSION}-win32.win32.x86_64.zip
DOWNLOAD_URL=${2:-$DEFAULT_URL}

echo "=================================================="
echo " Construyendo Instalador NSIS para $APP_NAME v$VERSION"
echo "=================================================="

# Comprobar herramientas necesarias
for cmd in wget unzip makensis; do
    if ! command -v $cmd &> /dev/null; then
        echo "❌ Error: El comando '$cmd' no está instalado. Por favor instálalo e intenta de nuevo."
        exit 1
    fi
done

# =========================================================
# 1. PREPARAR ENTORNO Y DESCARGAR
# =========================================================
TMP_DIR=$(mktemp -d -t nsis-build-XXXXXX)
echo "📁 Directorio temporal de trabajo: $TMP_DIR"
cd "$TMP_DIR" || exit 1

echo "📥 Descargando binarios desde: $DOWNLOAD_URL"
if ! wget -q --show-progress "$DOWNLOAD_URL" -O app.zip; then
    echo "❌ Error: No se pudo descargar el archivo. Verifica la URL o tu conexión."
    rm -rf "$TMP_DIR"
    exit 1
fi

# =========================================================
# 2. EXTRAER BINARIOS
# =========================================================
echo "📦 Extrayendo archivos..."
mkdir -p app_ext
unzip -q app.zip -d app_ext

# Detectar si el ZIP tiene una carpeta raíz interior o los archivos sueltos
if [ $(ls -1 app_ext | wc -l) -eq 1 ] && [ -d "app_ext/$(ls -1 app_ext)" ]; then
    BASE_EXTRACT_DIR="app_ext/$(ls -1 app_ext)"
else
    BASE_EXTRACT_DIR="app_ext"
fi

# Buscar dinámicamente el nombre exacto del archivo JAR
JAR_FILENAME=$(basename $(ls "$BASE_EXTRACT_DIR"/*.jar | head -n 1))

# =========================================================
# 3. GENERAR SCRIPT NSIS DINÁMICAMENTE
# =========================================================
echo "📝 Generando script NSIS al vuelo..."

# Se usa cat <<EOF para escribir el script. Las variables de bash como $APP_NAME
# se inyectan solas, pero las variables de NSIS como \$INSTDIR llevan una barra
# invertida para que bash no las reemplace.
cat <<EOF > build.nsi
OutFile "$ORIGINAL_DIR/${APP_NAME}-v${VERSION}-setup.exe"
Name "$APP_NAME $VERSION"
InstallDir "\$PROGRAMFILES64\\$APP_NAME"
RequestExecutionLevel admin

!include "MUI2.nsh"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "$ORIGINAL_DIR/license.txt"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "Spanish"
!insertmacro MUI_LANGUAGE "English"

Function .onInit
  ; Display the language selection dialog
  !insertmacro MUI_LANGDLL_DISPLAY
FunctionEnd

Section "Instalar"
  SetOutPath "\$INSTDIR"

  ; Usamos slash normal (/) para indicar rutas de compilación en Linux
  File "$BASE_EXTRACT_DIR/$JAR_FILENAME"
  File "$BASE_EXTRACT_DIR/jisocreator.bat"

  SetOutPath "\$INSTDIR\\lib"
  File "$BASE_EXTRACT_DIR/lib/*.jar"
  File "$ORIGINAL_DIR/jisocreator.ico"

  SetOutPath "\$INSTDIR"
  WriteUninstaller "\$INSTDIR\\uninstall.exe"

  ; Rutas de Windows llevan doble backslash (\\) en el script generado
  CreateDirectory "\$SMPROGRAMS\\$APP_NAME"
  CreateShortCut "\$SMPROGRAMS\\$APP_NAME\\$APP_NAME.lnk" "\$INSTDIR\\jisocreator.bat" "" "\$INSTDIR\\jisocreator.ico" 0
  CreateShortCut "\$SMPROGRAMS\\$APP_NAME\\Desinstalar.lnk" "\$INSTDIR\\uninstall.exe"
  CreateShortCut "\$DESKTOP\\$APP_NAME.lnk" "\$INSTDIR\\jisocreator.bat" "" "\$INSTDIR\\jisocreator.ico" 0
SectionEnd

Section "Uninstall"
  Delete "\$INSTDIR\\$JAR_FILENAME"
  Delete "\$INSTDIR\\jisocreator.bat"
  Delete "\$INSTDIR\\uninstall.exe"

  Delete "\$INSTDIR\\lib\\*.jar"
  RMDir "\$INSTDIR\\lib"

  RMDir "\$INSTDIR"

  Delete "\$DESKTOP\\$APP_NAME.lnk"
  RMDir /r "\$SMPROGRAMS\\$APP_NAME"
SectionEnd
EOF

# =========================================================
# 4. COMPILAR INSTALADOR
# =========================================================
echo "⚙️  Compilando instalador con NSIS..."
if makensis build.nsi > nsis_build.log; then
    echo "✅ ¡Instalador creado con éxito!"
    echo "🚀 Archivo generado: ${APP_NAME}-v${VERSION}-setup.exe"
else
    echo "❌ Error al compilar con NSIS. Revisa el log: $TMP_DIR/nsis_build.log"
    # Salimos sin borrar el temporal para que puedas depurar
    exit 1
fi

# =========================================================
# 5. LIMPIEZA
# =========================================================
echo "🧹 Limpiando archivos temporales..."
rm -rf "$TMP_DIR"
cd "$ORIGINAL_DIR" || exit
