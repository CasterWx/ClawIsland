#!/bin/bash
set -e

echo "🚀 Building ClawIsLand for Release..."
xcodebuild -project ClawIsLand.xcodeproj -scheme ClawIsLand -configuration Release build | xcpretty || xcodebuild -project ClawIsLand.xcodeproj -scheme ClawIsLand -configuration Release build -quiet

echo "📦 Installing to /Applications..."
# Find the build path
BUILD_DIR=$(xcodebuild -project ClawIsLand.xcodeproj -scheme ClawIsLand -configuration Release -showBuildSettings | grep -m 1 "TARGET_BUILD_DIR" | grep -oE "\/.*")
APP_PATH="$BUILD_DIR/ClawIsLand.app"

if [ -d "$APP_PATH" ]; then
    # Kill the app if it's already running
    pkill -x "ClawIsLand" || true
    
    # Remove old version
    rm -rf "/Applications/ClawIsLand.app"
    
    # Copy new version
    cp -R "$APP_PATH" "/Applications/"
    
    echo "✅ Successfully installed ClawIsLand to /Applications!"
    echo "🎉 You can now launch it from Launchpad or Spotlight."
else
    echo "❌ Build failed or could not find .app bundle at $APP_PATH"
    exit 1
fi
