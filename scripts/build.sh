#!/bin/zsh
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TASK_ROOT"
export CLANG_MODULE_CACHE_PATH="$TASK_ROOT/.build/ModuleCache"
export SWIFT_MODULECACHE_PATH="$TASK_ROOT/.build/ModuleCache"
swift build --disable-sandbox --cache-path "$TASK_ROOT/.build/cache" -c release --product ProjectBoard
TASK_NATIVE_BIN="$(swift build --disable-sandbox --cache-path "$TASK_ROOT/.build/cache" -c release --show-bin-path)"
if [[ "${1:-}" == "--universal" ]]; then
    swift build --disable-sandbox --cache-path "$TASK_ROOT/.build/cache" --scratch-path "$TASK_ROOT/.build/intel" --triple x86_64-apple-macosx13.0 -c release --product ProjectBoard
    TASK_INTEL_BIN="$(swift build --disable-sandbox --cache-path "$TASK_ROOT/.build/cache" --scratch-path "$TASK_ROOT/.build/intel" --triple x86_64-apple-macosx13.0 -c release --show-bin-path)"
fi
TASK_STAGING="$(mktemp -d "$TASK_ROOT/.build/AppBundle.XXXXXX")"
TASK_APP="$TASK_STAGING/归拢.app"
mkdir -p "$TASK_APP/Contents/MacOS" "$TASK_APP/Contents/Resources"
if [[ "${1:-}" == "--universal" ]]; then
    lipo -create "$TASK_NATIVE_BIN/ProjectBoard" "$TASK_INTEL_BIN/ProjectBoard" -output "$TASK_APP/Contents/MacOS/ProjectBoard"
else
    cp "$TASK_NATIVE_BIN/ProjectBoard" "$TASK_APP/Contents/MacOS/ProjectBoard"
fi
cp "$TASK_ROOT/Resources/Info.plist" "$TASK_APP/Contents/Info.plist"
swift scripts/make-icon.swift "$TASK_ROOT/.build/AppIcon.iconset" "$TASK_APP/Contents/Resources/AppIcon.icns"
# Local ad-hoc signature. No App Sandbox entitlement is added.
codesign --force --sign - "$TASK_APP"
codesign --verify --deep --strict "$TASK_APP"
TASK_OUTPUT_DIRECTORY="${BOARD_OUTPUT_DIRECTORY:-$TASK_ROOT/build}"
mkdir -p "$TASK_OUTPUT_DIRECTORY" "$TASK_ROOT/.build/PreviousBuilds"
if [[ -d "$TASK_OUTPUT_DIRECTORY/归拢.app" ]]; then
    TASK_PREVIOUS="$(mktemp -d "$TASK_ROOT/.build/PreviousBuilds/build.XXXXXX")"
    mv "$TASK_OUTPUT_DIRECTORY/归拢.app" "$TASK_PREVIOUS/归拢.app"
fi
mv "$TASK_APP" "$TASK_OUTPUT_DIRECTORY/归拢.app"
printf '已生成：%s\n' "$TASK_OUTPUT_DIRECTORY/归拢.app"
