#!/bin/bash
# Acceptance check for the global settings screen.
#
# Renders every value the controls can produce through the app's own writer, drops each into a
# throwaway CODEX_HOME, and asks the real CLI whether the config loads. Slow (each doctor run
# does network checks), so it is a script, not a test.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="$(mktemp -d)/verify-global-settings"
echo "compiling the checker..."
swiftc -O -parse-as-library -o "$OUT" Sources/CodexBridgerCore/*.swift scripts/verify-global-settings.swift
echo "running..."
exec "$OUT" "$@"
