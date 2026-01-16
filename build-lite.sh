#!/bin/bash

set -e

# Configuration - LITE VERSION (No bundled Ghostscript)
APP_NAME="CleverGhost"
BUNDLE_ID="com.cleverghost.app"
VERSION="1.0.0"
BUILD_NUMBER="1"
TEAM_ID="UM63FN2P72"

# Developer ID signing identity (for notarization, NOT App Store)
SIGNING_IDENTITY="Developer ID Application: Lale Taneri (UM63FN2P72)"

echo "========================================="
echo "Building CleverGhost Lite $VERSION (No Ghostscript)"
echo "========================================="

# Clean previous builds
rm -rf .build
rm -rf build-lite

# Build release binary
echo "Building release binary..."
swift build -c release

# Create app bundle structure
BUILD_DIR="build-lite"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"
mkdir -p dist

# Copy binary
cp ".build/release/$APP_NAME" "$MACOS_DIR/"

# App Icon
if [ -f "CleverGhost.icns" ]; then
    echo "Using CleverGhost.icns..."
    cp "CleverGhost.icns" "$RESOURCES_DIR/AppIcon.icns"
elif [ -f "assets/icon.png" ]; then
    echo "Generating AppIcon.icns from assets/icon.png..."
    ICONSET_DIR="MyIcon.iconset"
    mkdir -p "$ICONSET_DIR"

    # Generate icons with sips
    sips -z 16 16     "assets/icon.png" --out "$ICONSET_DIR/icon_16x16.png" > /dev/null
    sips -z 32 32     "assets/icon.png" --out "$ICONSET_DIR/icon_16x16@2x.png" > /dev/null
    sips -z 32 32     "assets/icon.png" --out "$ICONSET_DIR/icon_32x32.png" > /dev/null
    sips -z 64 64     "assets/icon.png" --out "$ICONSET_DIR/icon_32x32@2x.png" > /dev/null
    sips -z 128 128   "assets/icon.png" --out "$ICONSET_DIR/icon_128x128.png" > /dev/null
    sips -z 256 256   "assets/icon.png" --out "$ICONSET_DIR/icon_128x128@2x.png" > /dev/null
    sips -z 256 256   "assets/icon.png" --out "$ICONSET_DIR/icon_256x256.png" > /dev/null
    sips -z 512 512   "assets/icon.png" --out "$ICONSET_DIR/icon_256x256@2x.png" > /dev/null
    sips -z 512 512   "assets/icon.png" --out "$ICONSET_DIR/icon_512x512.png" > /dev/null
    sips -z 1024 1024 "assets/icon.png" --out "$ICONSET_DIR/icon_512x512@2x.png" > /dev/null

    # Convert to icns
    iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
    rm -rf "$ICONSET_DIR"
    echo "AppIcon.icns generated successfully."
else
    echo "Warning: No icon file found (checked CleverGhost.icns and assets/icon.png)"
fi

# NOTE: No Ghostscript bundle copied - users must install via Homebrew

# Create Info.plist
cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>PDF Document</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>com.adobe.pdf</string>
            </array>
        </dict>
    </array>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
</dict>
</plist>
PLIST

echo ""
echo "Signing app bundle with hardened runtime..."

# Sign the main binary with hardened runtime
codesign --force --options runtime --sign "$SIGNING_IDENTITY" "$MACOS_DIR/$APP_NAME"

# Sign the entire app bundle
codesign --force --options runtime --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"

echo "Verifying signature..."
codesign --verify --verbose "$APP_BUNDLE"

# Create DMG
DMG_NAME="$APP_NAME-$VERSION-Lite.dmg"
echo ""
echo "Creating DMG for distribution..."

# Use a specific volume name to avoid conflicts if already mounted
hdiutil create -volname "${APP_NAME} Lite ${VERSION}" -srcfolder "$APP_BUNDLE" -ov -format UDZO "dist/$DMG_NAME"

echo ""
echo "========================================="
echo "Build Complete!"
echo "========================================="
echo ""
echo "App bundle: $APP_BUNDLE"
echo "DMG file: dist/$DMG_NAME"
echo ""
echo "This LITE version requires users to install Ghostscript via Homebrew:"
echo "  brew install ghostscript"
echo ""
echo "NOTE: Notarization skipped. Run notarization separately when ready."
echo ""
