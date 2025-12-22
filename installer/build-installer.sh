#!/bin/bash
# installer/build-installer.sh

set -e

VERSION="0.1"
PRODUCT_NAME="mcpwa"
IDENTIFIER="com.crispapp.mcpwa"

SIGN_ID="Developer ID Application: CRISP APP STUDIO LLC (L44NEN6XKE)"
INSTALLER_SIGN_ID="Developer ID Installer: CRISP APP STUDIO LLC (L44NEN6XKE)"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/../Build"
PKG_ROOT="$BUILD_DIR/pkg_root"

echo "=== Building mcpwa Release ==="

xcodebuild -project "$PROJECT_DIR/mcpwa.xcodeproj" \
           -scheme mcpwa \
           -configuration Release \
           -derivedDataPath "$BUILD_DIR" \
           ARCHS="arm64 x86_64" \
           ONLY_ACTIVE_ARCH=NO \
           clean build

xcodebuild -project "$PROJECT_DIR/mcpwa.xcodeproj" \
           -scheme mcp-shim \
           -configuration Release \
           -derivedDataPath "$BUILD_DIR" \
           ARCHS="arm64 x86_64" \
           ONLY_ACTIVE_ARCH=NO \
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

echo "=== Signing mcp-shim ==="
codesign --force --verify --verbose \
         --sign "$SIGN_ID" \
         --timestamp \
         --options runtime \
         "$SHIM_PATH"

echo "=== Embedding mcp-shim in app bundle ==="
cp "$SHIM_PATH" "$APP_PATH/Contents/MacOS/"

echo "=== Embedding uninstall script ==="
cp "$SCRIPT_DIR/scripts/uninstall.sh" "$APP_PATH/Contents/Resources/"
chmod +x "$APP_PATH/Contents/Resources/uninstall.sh"

echo "=== Signing app bundle (stripping debug entitlements) ==="
codesign --force --verify --verbose \
         --sign "$SIGN_ID" \
         --timestamp \
         --options runtime \
         --deep \
         "$APP_PATH"

echo "=== Preparing package root ==="
rm -rf "$PKG_ROOT"
mkdir -p "$PKG_ROOT/Applications"
cp -R "$APP_PATH" "$PKG_ROOT/Applications/"

echo "=== Building and signing PKG ==="
pkgbuild --root "$PKG_ROOT" \
         --component-plist "$SCRIPT_DIR/component.plist" \
         --scripts "$SCRIPT_DIR/scripts" \
         --identifier "$IDENTIFIER" \
         --version "$VERSION" \
         --install-location "/" \
         --sign "$INSTALLER_SIGN_ID" \
         "$BUILD_DIR/$PRODUCT_NAME-$VERSION.pkg"

echo "Installer: $BUILD_DIR/$PRODUCT_NAME-$VERSION.pkg"

echo "=== Notarize ==="
xcrun notarytool submit "$BUILD_DIR/$PRODUCT_NAME-$VERSION.pkg" \
                        --apple-id "andryignatov@gmail.com" \
                        --team-id "L44NEN6XKE" \
                        --password "rmpu-pqnw-ztco-tkbi" \
                        --wait

echo "=== Staple ==="
xcrun stapler staple "$BUILD_DIR/$PRODUCT_NAME-$VERSION.pkg"

echo "=== Done ==="