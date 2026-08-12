#!/bin/zsh

set -euo pipefail

SCRIPT_DIRECTORY="${0:A:h}"
PROJECT_DIRECTORY="${SCRIPT_DIRECTORY:h}"
CONFIGURATION="${1:-release}"

cd "$PROJECT_DIRECTORY"
swift build -c "$CONFIGURATION"
BIN_DIRECTORY="$(swift build -c "$CONFIGURATION" --show-bin-path)"
APP_DIRECTORY="$PROJECT_DIRECTORY/.build/Branch.app"
CONTENTS_DIRECTORY="$APP_DIRECTORY/Contents"
MACOS_DIRECTORY="$CONTENTS_DIRECTORY/MacOS"
RESOURCES_DIRECTORY="$CONTENTS_DIRECTORY/Resources"
ICONSET_DIRECTORY="$PROJECT_DIRECTORY/.build/Branch.iconset"

mkdir -p "$MACOS_DIRECTORY" "$RESOURCES_DIRECTORY" "$ICONSET_DIRECTORY"
cp "$BIN_DIRECTORY/Branch" "$MACOS_DIRECTORY/Branch"
cp "$PROJECT_DIRECTORY/AppResources/Info.plist" "$CONTENTS_DIRECTORY/Info.plist"
cp "$PROJECT_DIRECTORY/AppResources/BranchIcon.png" "$RESOURCES_DIRECTORY/BranchIcon.png"

SOURCE_ICON="$PROJECT_DIRECTORY/AppResources/BranchIcon.png"
sips -z 16 16 "$SOURCE_ICON" --out "$ICONSET_DIRECTORY/icon_16x16.png" >/dev/null
sips -z 32 32 "$SOURCE_ICON" --out "$ICONSET_DIRECTORY/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$SOURCE_ICON" --out "$ICONSET_DIRECTORY/icon_32x32.png" >/dev/null
sips -z 64 64 "$SOURCE_ICON" --out "$ICONSET_DIRECTORY/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$SOURCE_ICON" --out "$ICONSET_DIRECTORY/icon_128x128.png" >/dev/null
sips -z 256 256 "$SOURCE_ICON" --out "$ICONSET_DIRECTORY/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$SOURCE_ICON" --out "$ICONSET_DIRECTORY/icon_256x256.png" >/dev/null
sips -z 512 512 "$SOURCE_ICON" --out "$ICONSET_DIRECTORY/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$SOURCE_ICON" --out "$ICONSET_DIRECTORY/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$SOURCE_ICON" --out "$ICONSET_DIRECTORY/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET_DIRECTORY" -o "$RESOURCES_DIRECTORY/BranchIcon.icns"

codesign --force --deep --sign - "$APP_DIRECTORY"
echo "$APP_DIRECTORY"
