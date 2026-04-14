#!/bin/bash
set -euo pipefail

# Foundry Build Script
# Builds the Swift package and creates a macOS .app bundle

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build"
APP_NAME="Foundry"
BUNDLE_ID="com.foundry.app"
APP_DIR="$PROJECT_DIR/$APP_NAME.app"

echo "=== Building Foundry ==="
echo "Project: $PROJECT_DIR"
echo ""

# Step 1: Build the Swift package
echo "[1/4] Compiling Swift package..."
cd "$PROJECT_DIR"
swift build -c release 2>&1

BINARY_PATH=$(swift build -c release --show-bin-path)/$APP_NAME
echo "Binary: $BINARY_PATH"

if [ ! -f "$BINARY_PATH" ]; then
    echo "ERROR: Binary not found at $BINARY_PATH"
    exit 1
fi

# Step 2: Create .app bundle structure
echo "[2/4] Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Step 3: Copy binary
echo "[3/4] Copying binary..."
cp "$BINARY_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"

# Step 4: Create Info.plist
echo "[4/4] Writing Info.plist..."
cat > "$APP_DIR/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Foundry</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.foundry.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Foundry</string>
    <key>CFBundleDisplayName</key>
    <string>Foundry</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Foundry. All rights reserved.</string>
</dict>
</plist>
PLIST

echo ""
echo "=== Build Complete ==="
echo "App bundle: $APP_DIR"
echo ""
echo "To run:"
echo "  open $APP_DIR"
echo ""
echo "To install:"
echo "  cp -r $APP_DIR /Applications/"
