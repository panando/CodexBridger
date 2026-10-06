#!/bin/bash
# Regenerates the committed example files in docs/examples using the real
# activation path.
#
# The generator is compiled directly against the core sources with swiftc instead
# of being a second SwiftPM executable target, which keeps the shipped package to a
# single product.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUT="${1:-docs/examples}"
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/swiftc-module-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH"

BIN="$ROOT/.build/gen_sample"
swiftc -O \
    -module-cache-path "$CLANG_MODULE_CACHE_PATH" \
    $(find "$ROOT/Sources/CodexBridgerCore" -name "*.swift" | sort) \
    "$ROOT/tools/gen_sample/main.swift" \
    -o "$BIN"

rm -rf "$OUT"
"$BIN" --out "$OUT"

# Codex creates a scratch directory when it reads a CODEX_HOME; keep the example
# directory to just the generated files.
rm -rf "$OUT/tmp"
