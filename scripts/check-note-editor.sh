#!/bin/zsh
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TASK_ROOT"
export CLANG_MODULE_CACHE_PATH="$TASK_ROOT/.build/ModuleCache"
export SWIFT_MODULECACHE_PATH="$TASK_ROOT/.build/ModuleCache"
mkdir -p "$TASK_ROOT/.build/NoteEditorChecks"
swiftc Sources/ProjectBoard/NoteImageEditor.swift Tests/NoteEditorTests/main.swift -o "$TASK_ROOT/.build/NoteEditorChecks/checks"
exec "$TASK_ROOT/.build/NoteEditorChecks/checks"
