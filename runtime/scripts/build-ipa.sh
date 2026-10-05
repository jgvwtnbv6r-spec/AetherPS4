#!/usr/bin/env bash
# Builds the unsigned AetherPS4 iOS app as an .ipa using the repo checkout on the
# runner. This avoids the local-machine absolute paths baked into the Xcode project.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT_DIR="$REPO_ROOT/AetherPS4-iOS"
SCHEME="AetherPS4-iOS"
CONFIGURATION="Release"
DEST_DIR="${1:-$HOME/Desktop}"
GENERATED_HEADERS_DIR="$PROJECT_DIR/GeneratedHeaders"

mkdir -p "$GENERATED_HEADERS_DIR"

# The Obj-C bridging header imports repo headers that are not in the local checkout on CI.
# Copy them into a repo-local directory so that Xcode does not depend on a developer's
# machine-specific path.
for header in \
    "$REPO_ROOT/src/platform/ios/shadps4_ios_api.h" \
    "$REPO_ROOT/src/core/pkg_extract/pkg_extractor.h" \
    "$REPO_ROOT/src/core/sysmodules_import/sysmodules_import.h" \
    "$REPO_ROOT/src/core/user_profile_bridge/user_profile_bridge.h"
do
    if [[ ! -f "$header" ]]; then
        echo "error: missing required header: $header" >&2
        exit 1
    fi
    cp "$header" "$GENERATED_HEADERS_DIR/"
done

# Make the include path explicit for this runner instead of relying on the old absolute
# paths embedded in the Xcode project metadata.
export HEADER_SEARCH_PATHS="$(inherited) $GENERATED_HEADERS_DIR $REPO_ROOT/src/platform/ios $REPO_ROOT/src/core/pkg_extract $REPO_ROOT/src/core/sysmodules_import $REPO_ROOT/src/core/user_profile_bridge"

cd "$PROJECT_DIR"

echo "==> Building $SCHEME ($CONFIGURATION, iphoneos, unsigned)"
xcodebuild \
    -project "$SCHEME.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -sdk iphoneos \
    -destination "generic/platform=iOS" \
    CODE_SIGNING_ALLOWED=NO \
    HEADER_SEARCH_PATHS="$HEADER_SEARCH_PATHS" \
    build

echo "==> Locating build product"
BUILD_DIR=$(xcodebuild \
    -project "$SCHEME.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -sdk iphoneos \
    -showBuildSettings 2>/dev/null | awk -F'= ' '/ CONFIGURATION_BUILD_DIR =/ {print $2; exit}')
APP_PATH="$BUILD_DIR/$SCHEME.app"

if [[ ! -d "$APP_PATH" ]]; then
    echo "error: built app not found at $APP_PATH" >&2
    exit 1
fi

echo "==> Packaging IPA from $APP_PATH"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

mkdir -p "$WORK_DIR/Payload"
cp -R "$APP_PATH" "$WORK_DIR/Payload/"

mkdir -p "$DEST_DIR"
IPA_PATH="$DEST_DIR/$SCHEME.ipa"
rm -f "$IPA_PATH"

(cd "$WORK_DIR" && zip -qr "$IPA_PATH" Payload)

echo "==> Done: $IPA_PATH"
