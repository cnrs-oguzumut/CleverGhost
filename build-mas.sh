#!/bin/bash

# build-mas.sh
# Builds CleverGhost for Mac App Store submission
# Sandboxed, bundled with Ghostscript, packaged as PKG

set -e

# Configuration
APP_NAME="CleverGhost"
BUNDLE_ID="com.cleverghost.app"
VERSION="1.1.0"
BUILD_NUMBER="1"
DIST_DIR="dist"

# Signing Identities
APP_CERT="3rd Party Mac Developer Application: Lale Taneri (UM63FN2P72)"
INSTALLER_CERT="3rd Party Mac Developer Installer: Lale Taneri (UM63FN2P72)"

echo "========================================="
echo "Building CleverGhost for Mac App Store"
echo "========================================="
echo "Bundle ID: $BUNDLE_ID"
echo "Version: $VERSION ($BUILD_NUMBER)"

# Clean previous builds
rm -rf .build
rm -rf build-mas
mkdir -p "$DIST_DIR"

# Build release binary
echo "Building release binary..."
swift build -c release

# Create app bundle structure
BUILD_DIR="build-mas"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy binary
cp ".build/release/$APP_NAME" "$MACOS_DIR/"

# Handle Icon
echo ""
echo "Processing Icon..."
if [ -f "CleverGhost.icns" ]; then
    echo "Using CleverGhost.icns..."
    cp "CleverGhost.icns" "$RESOURCES_DIR/AppIcon.icns"
elif [ -f "assets/icon.png" ]; then
    echo "Converting assets/icon.png to AppIcon.icns..."

    ICONSET_DIR="MyIcon.iconset"
    mkdir -p "$ICONSET_DIR"

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

    iconutil -c icns "$ICONSET_DIR"
    cp "MyIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
    rm -rf "$ICONSET_DIR"
    rm "MyIcon.icns"

    echo "Icon processed successfully."
else
    echo "Warning: No icon file found"
fi

# Prepare and copy Ghostscript bundle
echo ""
echo "Preparing Ghostscript bundle..."
./prepare-ghostscript.sh

echo "Copying Ghostscript bundle to app..."
if [ -d "ghostscript-bundle" ]; then
    cp -R "ghostscript-bundle" "$RESOURCES_DIR/ghostscript"
    echo "Ghostscript bundle copied to $RESOURCES_DIR/ghostscript"
else
    echo "Error: ghostscript-bundle directory not found!"
    exit 1
fi

# Create Info.plist
cat > "$CONTENTS_DIR/Info.plist" << EOF
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
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026. All rights reserved.</string>
</dict>
</plist>
EOF

echo ""
echo "Signing Ghostscript binaries and libraries..."
# Sign all dylibs first
if [ -d "$RESOURCES_DIR/ghostscript/lib" ]; then
    for dylib in "$RESOURCES_DIR"/ghostscript/lib/*.dylib; do
        if [ -f "$dylib" ]; then
            echo "  Signing: $(basename $dylib)"
            codesign --force --sign "$APP_CERT" \
                --entitlements "Ghostscript.entitlements" \
                --options runtime \
                --timestamp "$dylib"
        fi
    done
fi

# Sign the Ghostscript binary with entitlements
if [ -f "$RESOURCES_DIR/ghostscript/bin/gs" ]; then
    echo "  Signing: gs binary"
    codesign --force --sign "$APP_CERT" \
        --entitlements "Ghostscript.entitlements" \
        --options runtime \
        --timestamp "$RESOURCES_DIR/ghostscript/bin/gs"
fi

echo ""
echo "Signing main app bundle with sandboxing entitlements..."
codesign --deep --force --sign "$APP_CERT" \
    --entitlements "CleverGhost.entitlements" \
    --options runtime \
    --timestamp "$APP_BUNDLE"

echo "Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo ""
echo "Fixing file permissions for App Store submission..."
# Ensure all files are readable by non-root users
find "$APP_BUNDLE" -type f -exec chmod a+r {} \;
find "$APP_BUNDLE" -type d -exec chmod a+rx {} \;

echo ""
echo "Creating installer package..."
PKG_NAME="$APP_NAME-$VERSION-MAS.pkg"
productbuild --component "$APP_BUNDLE" /Applications \
    --sign "$INSTALLER_CERT" \
    "$DIST_DIR/$PKG_NAME"

echo ""
echo "========================================="
echo "Build Complete!"
echo "========================================="
echo "App bundle: $APP_BUNDLE"
echo "Installer: $DIST_DIR/$PKG_NAME"
echo ""
echo "This package is ready for Mac App Store submission via App Store Connect."
echo ""
echo "Next steps:"
echo "1. Upload PKG to App Store Connect using Transporter"
echo "2. Complete app metadata in App Store Connect"
echo "3. Submit for review"
echo ""
