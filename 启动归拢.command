#!/bin/zsh
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")" && pwd)"
if [[ ! -d "$TASK_ROOT/build/归拢.app" ]]; then
    /bin/zsh "$TASK_ROOT/scripts/build.sh"
fi
open "$TASK_ROOT/build/归拢.app"
