#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$TASK_ROOT/.build/module-cache"
swiftc -module-cache-path "$TASK_ROOT/.build/module-cache" "$TASK_ROOT/Sources/SendRate.swift" "$TASK_ROOT/Tests/main.swift" -o "$TASK_ROOT/.build/schedule-tests"
"$TASK_ROOT/.build/schedule-tests"
