#!/bin/zsh
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TASK_ROOT"
export CLANG_MODULE_CACHE_PATH="$TASK_ROOT/.build/ModuleCache"
export SWIFT_MODULECACHE_PATH="$TASK_ROOT/.build/ModuleCache"
swift build --disable-sandbox --cache-path .build/cache --target BoardCore
TASK_BIN="$(swift build --disable-sandbox --cache-path .build/cache --show-bin-path)"
mkdir -p "$TASK_ROOT/.build/NoteLayoutChecks"
swiftc -target "$(uname -m)-apple-macosx13.0" -I "$TASK_BIN/Modules" \
    Sources/ProjectBoard/{BoardStore,ContentView,FilesPanel,LinksPanel,NoteImageEditor,NotesPanel,TasksPanel,Theme}.swift \
    "$TASK_BIN"/BoardCore.build/*.swift.o Tests/NoteLayoutTests/main.swift \
    -o "$TASK_ROOT/.build/NoteLayoutChecks/checks"
TASK_FIXTURE="$(mktemp -d "$TASK_ROOT/.build/NoteLayoutChecks/Library.XXXXXX")"
trap 'rm -rf "$TASK_FIXTURE"' EXIT
"$TASK_ROOT/.build/NoteLayoutChecks/checks" --library "$TASK_FIXTURE"
