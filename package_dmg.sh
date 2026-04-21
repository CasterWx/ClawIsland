#!/bin/bash
set -e

echo "🚀 Building ClawIsLand for Release..."
xcodebuild -project ClawIsLand.xcodeproj -scheme ClawIsLand -configuration Release build | xcpretty || xcodebuild -project ClawIsLand.xcodeproj -scheme ClawIsLand -configuration Release build -quiet

echo "📦 Finding build directory..."
BUILD_DIR=$(xcodebuild -project ClawIsLand.xcodeproj -scheme ClawIsLand -configuration Release -showBuildSettings | grep -m 1 "TARGET_BUILD_DIR" | grep -oE "\/.*")
APP_PATH="$BUILD_DIR/ClawIsLand.app"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ Build failed or could not find .app bundle at $APP_PATH"
    exit 1
fi

echo "🗂️  Preparing DMG staging area..."
STAGING_DIR="build/dmg_staging"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

echo "➡️  Copying App to staging..."
cp -R "$APP_PATH" "$STAGING_DIR/"

echo "🔗 Creating Applications symlink..."
ln -s /Applications "$STAGING_DIR/Applications"

DMG_NAME="ClawIsLand.dmg"
echo "💿 Creating final Disk Image ($DMG_NAME)..."
rm -f "$DMG_NAME"
hdiutil create -volname "ClawIsLand" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_NAME"

echo "🧹 Cleaning up staging area..."
rm -rf "$STAGING_DIR"

echo "🎉 Successfully created $DMG_NAME! It is ready to be uploaded to GitHub Releases."
