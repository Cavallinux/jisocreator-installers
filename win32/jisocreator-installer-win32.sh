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
JRE_URL=https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.11%2B10/OpenJDK21U-jre_x64_windows_hotspot_21.0.11_10.zip
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

echo "📥 Descargando binario de JISOCREATOR desde: $DOWNLOAD_URL"
if ! wget -q --show-progress "$DOWNLOAD_URL" -O app.zip; then
    echo "❌ Error: No se pudo descargar el archivo. Verifica la URL o tu conexión."
    rm -rf "$TMP_DIR"
    exit 1
fi

echo "📥 Descargando JRE desde: $JRE_URL"
if ! wget -q --show-progress "$JRE_URL" -O jre.zip; then
    echo "❌ Error: No se pudo descargar el archivo. Verifica la URL o tu conexión."
    rm -rf "$TMP_DIR"
    exit 1
fi

# Asegurar que el banner lateral de NSIS se genere dinámicamente
if command -v magick &> /dev/null; then
    echo "🎨 Generando banner lateral de 164x314 para NSIS..."
    # Corta por la mitad izquierda y redimensiona estrictamente a BMP de 164x314
    magick -density 300 $ORIGINAL_DIR/jisocreator.svg -background white -alpha remove -crop 50%x100%+0+0 -resize 164x314! $ORIGINAL_DIR/nsis_banner.bmp
else
    echo "⚠️ ImageMagick no está instalado. Asegúrate de tener nsis_banner.bmp listo."
fi

# =========================================================
# 2. EXTRAER BINARIOS
# =========================================================
echo "📦 Extrayendo archivos..."
mkdir -p app_ext
mkdir -p jre_ext
unzip -q app.zip -d app_ext
unzip -q jre.zip -d jre_ext

# Detectar si el ZIP de JISOCREATOR tiene una carpeta raíz interior o los archivos sueltos
if [ $(ls -1 app_ext | wc -l) -eq 1 ] && [ -d "app_ext/$(ls -1 app_ext)" ]; then
    BASE_EXTRACT_DIR="app_ext/$(ls -1 app_ext)"
else
    BASE_EXTRACT_DIR="app_ext"
fi

# Detectar si el ZIP del jre tiene una carpeta raíz interior o los archivos sueltos
if [ $(ls -1 jre_ext | wc -l) -eq 1 ] && [ -d "jre_ext/$(ls -1 jre_ext)" ]; then
    JRE_EXTRACT_DIR="jre_ext/$(ls -1 jre_ext)"
else
    JRE_EXTRACT_DIR="jre_ext"
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
SetCompressor /SOLID lzma


!define MUI_ICON "$ORIGINAL_DIR/jisocreator.ico"
!define MUI_WELCOMEFINISHPAGE_BITMAP "$ORIGINAL_DIR/nsis_banner.bmp"
!include "MUI2.nsh"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "$ORIGINAL_DIR/license.txt"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!define MUI_ABORTWARNING
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "Spanish"
!insertmacro MUI_LANGUAGE "English"

LangString STRING_BRANDING \${LANG_ENGLISH} "$APP_NAME - Version $VERSION"
LangString STRING_BRANDING \${LANG_SPANISH} "$APP_NAME - Versión $VERSION"
BrandingText "\$(STRING_BRANDING)"

Function .onInit
  ; Display the language selection dialog
  !insertmacro MUI_LANGDLL_DISPLAY
FunctionEnd

Section "Instalar"
  SetOutPath "\$INSTDIR"

  ; Usamos slash normal (/) para indicar rutas de compilación en Linux
  File "$BASE_EXTRACT_DIR/$JAR_FILENAME"
  File "$BASE_EXTRACT_DIR/jisocreator.bat"
  File "$ORIGINAL_DIR/jisocreator.ico"

  SetOutPath "\$INSTDIR\\lib"
  File "$BASE_EXTRACT_DIR/lib/*.jar"

  SetOutPath "\$INSTDIR\\jre"
  File /r "$JRE_EXTRACT_DIR/*.*"

  SetOutPath "\$INSTDIR\\res\\mkisofs"
  File "$BASE_EXTRACT_DIR/res/mkisofs/*.ini"
  File "$BASE_EXTRACT_DIR/res/mkisofs/*.exe"
  File "$BASE_EXTRACT_DIR/res/mkisofs/*.dll"

  SetOutPath "\$INSTDIR"
  WriteUninstaller "\$INSTDIR\\uninstall.exe"

  ; Rutas de Windows llevan doble backslash (\\) en el script generado
  CreateDirectory "\$SMPROGRAMS\\$APP_NAME"
  CreateShortCut "\$SMPROGRAMS\\$APP_NAME\\$APP_NAME.lnk" "\$INSTDIR\\jisocreator.bat" "\$INSTDIR\\jisocreator.ico" 0
  CreateShortCut "\$SMPROGRAMS\\$APP_NAME\\Desinstalar.lnk" "\$INSTDIR\\uninstall.exe"
  CreateShortCut "\$DESKTOP\\$APP_NAME.lnk" "\$INSTDIR\\jisocreator.bat" "" "\$INSTDIR\\jisocreator.ico" 0
SectionEnd

Section "Uninstall"
  Delete "\$INSTDIR\\$JAR_FILENAME"
  Delete "\$INSTDIR\\jisocreator.bat"
  Delete "\$INSTDIR\\jisocreator.ico"
  Delete "\$INSTDIR\\uninstall.exe"

  Delete "\$INSTDIR\\lib\\*.jar"
  RMDir "\$INSTDIR\\lib"

  Delete "\$INSTDIR\\res\\mkisofs\\*.ini"
  Delete "\$INSTDIR\\res\\mkisofs\\*.exe"
  Delete "\$INSTDIR\\res\\mkisofs\\*.dll"
  RMDir /r "\$INSTDIR\\res"

  RMDir /r "\$INSTDIR\\jre"

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
