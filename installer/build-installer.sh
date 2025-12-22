#!/bin/bash
# installer/build-installer.sh

set -e

VERSION="0.1"
PRODUCT_NAME="mcpwa"
IDENTIFIER="com.crispapp.mcpwa"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/../Build"
PKG_ROOT="$BUILD_DIR/pkg_root"

echo "=== Building mcpwa Release ==="

xcodebuild -project "$PROJECT_DIR/mcpwa.xcodeproj" \
           -scheme mcpwa \
           -configuration Release \
           -derivedDataPath "$BUILD_DIR" \
           clean build

xcodebuild -project "$PROJECT_DIR/mcpwa.xcodeproj" \
           -scheme mcp-shim \
           -configuration Release \
           -derivedDataPath "$BUILD_DIR" \
           build

APP_PATH="$BUILD_DIR/Products/Release/mcpwa.app"
SHIM_PATH="$BUILD_DIR/Products/Release/mcp-shim"

if [ ! -d "$APP_PATH" ]; then
    echo "Error: mcpwa.app not found at $APP_PATH"
    exit 1
fi

if [ ! -f "$SHIM_PATH" ]; then
    echo "Error: mcp-shim not found at $SHIM_PATH"
    exit 1
fi

echo "=== Embedding mcp-shim in app bundle ==="
cp "$SHIM_PATH" "$APP_PATH/Contents/MacOS/"

echo "=== Embedding uninstall script ==="
cp "$SCRIPT_DIR/scripts/uninstall.sh" "$APP_PATH/Contents/Resources/"
chmod +x "$APP_PATH/Contents/Resources/uninstall.sh"

echo "=== Preparing package root ==="
rm -rf "$PKG_ROOT"
mkdir -p "$PKG_ROOT/Applications"
cp -R "$APP_PATH" "$PKG_ROOT/Applications/"

echo "=== Building PKG ==="

pkgbuild --root "$PKG_ROOT" \
         --component-plist "$BUILD_DIR/component.plist" \
         --scripts "$SCRIPT_DIR/scripts" \
         --identifier "$IDENTIFIER" \
         --version "$VERSION" \
         --install-location "/" \
         "$BUILD_DIR/$PRODUCT_NAME-$VERSION.pkg"

echo "=== Done ==="
echo "Installer: $BUILD_DIR/$PRODUCT_NAME-$VERSION.pkg"

