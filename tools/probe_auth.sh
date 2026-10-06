#!/bin/bash
# Probe which auth.json shapes the real Codex CLI accepts.
# Codex validates auth.json with serde, so malformed shapes surface as errors.
set -u
CODEX="/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
ROOT=/tmp/codexauth
rm -rf "$ROOT"; mkdir -p "$ROOT"

probe() {
  local name="$1"; local body="$2"
  local home="$ROOT/$name"
  mkdir -p "$home"
  printf '%s' "$body" > "$home/auth.json"
  echo "=== $name ==="
  CODEX_HOME="$home" "$CODEX" login status 2>&1 | grep -v "PATH aliases" | head -6
  echo "  [exit=$?]"
}

probe apikey_only '{"OPENAI_API_KEY":"sk-probe-123"}'
probe apikey_mode '{"auth_mode":"apikey","OPENAI_API_KEY":"sk-probe-123"}'
probe apikey_mode_extra '{"auth_mode":"apikey","OPENAI_API_KEY":"sk-probe-123","PROBE_KEY":"abc"}'
probe bogus_key '{"totally_bogus":"x"}'
probe invalid_json '{"OPENAI_API_KEY":'
probe empty '{}'
