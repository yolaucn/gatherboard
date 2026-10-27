#!/bin/zsh
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TASK_ROOT"
TASK_RELEASE_DIRECTORY="$TASK_ROOT/.build/ReleaseArtifact"
if [[ "${1:-}" != '--skip-build' ]]; then
    BOARD_OUTPUT_DIRECTORY="$TASK_RELEASE_DIRECTORY" /bin/zsh scripts/build.sh --universal
fi
TASK_APP="$TASK_RELEASE_DIRECTORY/归拢.app"
codesign --verify --deep --strict "$TASK_APP"
lipo "$TASK_APP/Contents/MacOS/ProjectBoard" -verify_arch arm64 x86_64
TASK_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$TASK_APP/Contents/Info.plist")"
TASK_PAYLOAD="$(mktemp -d "$TASK_ROOT/.build/DMGPayload.XXXXXX")"
ditto "$TASK_APP" "$TASK_PAYLOAD/归拢.app"
ln -s /Applications "$TASK_PAYLOAD/应用程序"
cp "$TASK_ROOT/Resources/安装说明.txt" "$TASK_PAYLOAD/安装说明.txt"
TASK_DOWNLOAD_DIRECTORY="$TASK_ROOT/website/dist/downloads"
mkdir -p "$TASK_DOWNLOAD_DIRECTORY"
TASK_DMG="$TASK_DOWNLOAD_DIRECTORY/归拢-$TASK_VERSION-universal.dmg"
if ! hdiutil create -volname '拖动归拢到应用程序' -srcfolder "$TASK_PAYLOAD" -format UDZO -fs HFS+ -ov "$TASK_DMG"; then
    # makehybrid creates an HFS+ filesystem directly, without a virtual disk device.
    # Conversion then adds the normal compressed UDIF container and checksums.
    TASK_BASE_DIRECTORY="$(mktemp -d "$TASK_ROOT/.build/DMGBase.XXXXXX")"
    hdiutil makehybrid -hfs -hfs-volume-name '拖动归拢到应用程序' -hfs-openfolder "$TASK_PAYLOAD" -o "$TASK_BASE_DIRECTORY/base.dmg" "$TASK_PAYLOAD"
    hdiutil convert "$TASK_BASE_DIRECTORY/base.dmg" -format UDZO -ov -o "$TASK_DMG"
fi
hdiutil verify "$TASK_DMG"
shasum -a 256 "$TASK_DMG"
printf '已生成：%s\n' "$TASK_DMG"
