#!/bin/bash
set -euo pipefail

# ============================================================
# Foundry Release Build — Sign, DMG, Notarize
# ============================================================

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Foundry"
BUNDLE_ID="com.foundry.app"
APP_DIR="$PROJECT_DIR/$APP_NAME.app"
DMG_NAME="Foundry-2.0.0.dmg"
DMG_PATH="$PROJECT_DIR/$DMG_NAME"
RESOURCES_DIR="$PROJECT_DIR/Resources"

# Signing & Notarization
SIGNING_IDENTITY="Developer ID Application: Simon-Pierre Boucher (3YM54G49SN)"
TEAM_ID="3YM54G49SN"
APPLE_ID="spbou4@icloud.com"
APP_PASSWORD="kmnu-cmfc-txwl-deuy"

echo "============================================================"
echo "  Foundry Release Build"
echo "============================================================"
echo ""

# ----------------------------------------------------------
# Step 1: Build release binary
# ----------------------------------------------------------
echo "[1/7] Building release binary..."
cd "$PROJECT_DIR"
swift build -c release 2>&1

BINARY_PATH="$(swift build -c release --show-bin-path)/$APP_NAME"
if [ ! -f "$BINARY_PATH" ]; then
    echo "ERROR: Binary not found at $BINARY_PATH"
    exit 1
fi
echo "  Binary: $BINARY_PATH"

# ----------------------------------------------------------
# Step 2: Create .app bundle
# ----------------------------------------------------------
echo "[2/7] Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy binary
cp "$BINARY_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"

# Copy icon
if [ -f "$RESOURCES_DIR/AppIcon.icns" ]; then
    cp "$RESOURCES_DIR/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
    echo "  Icon copied"
fi

# Write Info.plist
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
    <string>2.0.0</string>
    <key>CFBundleVersion</key>
    <string>2</string>
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
    <string>Copyright © 2026 Simon-Pierre Boucher. All rights reserved.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST
echo "  Info.plist written"

# Write entitlements
cat > "$PROJECT_DIR/Foundry.entitlements" << 'ENTITLEMENTS'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
</dict>
</plist>
ENTITLEMENTS
echo "  Entitlements written"

# ----------------------------------------------------------
# Step 3: Code sign
# ----------------------------------------------------------
echo "[3/7] Code signing..."
codesign --force --deep --options runtime \
    --sign "$SIGNING_IDENTITY" \
    --entitlements "$PROJECT_DIR/Foundry.entitlements" \
    --timestamp \
    "$APP_DIR" 2>&1

# Verify
codesign --verify --deep --strict --verbose=2 "$APP_DIR" 2>&1
echo "  Signature verified"

# ----------------------------------------------------------
# Step 4: Create DMG
# ----------------------------------------------------------
echo "[4/7] Creating DMG..."
rm -f "$DMG_PATH"

# Create a temporary DMG folder
DMG_STAGING="$PROJECT_DIR/.dmg-staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_DIR" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

# Create DMG
hdiutil create -volname "Foundry" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDZO \
    "$DMG_PATH" 2>&1

rm -rf "$DMG_STAGING"
echo "  DMG created: $DMG_PATH"

# ----------------------------------------------------------
# Step 5: Sign the DMG
# ----------------------------------------------------------
echo "[5/7] Signing DMG..."
codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG_PATH" 2>&1
echo "  DMG signed"

# ----------------------------------------------------------
# Step 6: Notarize
# ----------------------------------------------------------
echo "[6/7] Submitting for notarization..."
echo "  This may take a few minutes..."

xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --password "$APP_PASSWORD" \
    --team-id "$TEAM_ID" \
    --wait 2>&1

echo "  Notarization complete"

# ----------------------------------------------------------
# Step 7: Staple
# ----------------------------------------------------------
echo "[7/7] Stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH" 2>&1
echo "  Ticket stapled"

# ----------------------------------------------------------
# Done
# ----------------------------------------------------------
echo ""
echo "============================================================"
echo "  BUILD COMPLETE"
echo "============================================================"
echo "  App:  $APP_DIR"
echo "  DMG:  $DMG_PATH"
echo "  Size: $(du -h "$DMG_PATH" | cut -f1)"
echo ""
echo "  Ready for distribution!"
echo "============================================================"
