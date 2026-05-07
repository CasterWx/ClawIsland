#!/bin/bash
set -euo pipefail

PROJECT="ClawIsLand.xcodeproj"
SCHEME="ClawIsLand"
CONFIGURATION="${CONFIGURATION:-Release}"

echo "Building $SCHEME ($CONFIGURATION)..."

BUILD_ARGS=(-project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION")

# Allow signing to be controlled via env
if [ -n "${CODE_SIGN_IDENTITY:-}" ]; then
	BUILD_ARGS+=("CODE_SIGN_IDENTITY=$CODE_SIGN_IDENTITY" "CODE_SIGN_STYLE=Manual" "PROVISIONING_PROFILE_SPECIFIER=")
fi
if [ -n "${DEVELOPMENT_TEAM:-}" ]; then
	BUILD_ARGS+=("DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM")
fi

BUILD_ARGS+=(build)

xcodebuild "${BUILD_ARGS[@]}" 2>&1 | xcpretty || xcodebuild "${BUILD_ARGS[@]}" -quiet

# Extract build path and version
BUILD_DIR=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" -showBuildSettings 2>/dev/null | grep -m1 "TARGET_BUILD_DIR" | grep -oE "/.*")
APP_PATH="$BUILD_DIR/$SCHEME.app"
VERSION=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" -showBuildSettings 2>/dev/null | grep -m1 "MARKETING_VERSION" | grep -oE '[0-9.]+')

if [ ! -d "$APP_PATH" ]; then
	echo "Build failed or could not find .app at $APP_PATH" >&2
	exit 1
fi

echo "Built $SCHEME $VERSION at $APP_PATH"

# Create DMG
ARCH="${ARCH:-arm64}"
DMG_NAME="ClawIsLand-${VERSION}-mac-${ARCH}.dmg"
STAGING_DIR="build/dmg_staging"

echo "Creating $DMG_NAME..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_NAME"
hdiutil create -volname "$SCHEME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_NAME"
rm -rf "$STAGING_DIR"

# Optional notarization — runs against the DMG
if [ "${NOTARIZE:-false}" = "true" ]; then
	if [ -z "${APPLE_ID:-}" ] || [ -z "${APPLE_TEAM_ID:-}" ] || [ -z "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]; then
		echo "NOTARIZE=true but APPLE_ID, APPLE_TEAM_ID, or APPLE_APP_SPECIFIC_PASSWORD not set" >&2
		exit 1
	fi
	echo "Submitting DMG for notarization..."
	xcrun notarytool submit "$DMG_NAME" \
		--apple-id "$APPLE_ID" \
		--team-id "$APPLE_TEAM_ID" \
		--password "$APPLE_APP_SPECIFIC_PASSWORD" \
		--wait
	echo "Stapling notarization ticket..."
	xcrun stapler staple "$DMG_NAME"
	echo "Notarization complete."
fi

# SHA256 checksum
shasum -a 256 "$DMG_NAME" | awk '{print $1 "  " $2}' > "${DMG_NAME}.sha256"
echo "Checksum: $(cat "${DMG_NAME}.sha256")"

echo "Successfully created $DMG_NAME"

# Output for GitHub Actions
if [ -n "${GITHUB_OUTPUT:-}" ]; then
	echo "DMG=$DMG_NAME" >> "$GITHUB_OUTPUT"
	echo "VERSION=$VERSION" >> "$GITHUB_OUTPUT"
fi
