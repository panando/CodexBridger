#!/bin/bash
# Builds the throw-away CODEX_HOME used for the UI screenshots.
#
# It is a copy of docs/examples with the app state rewritten to match the provider that
# was on screen in the "before" capture, so before and after differ only in layout.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEMO="$ROOT/docs/ui/demo-home"

rm -rf "$DEMO"
cp -R "$ROOT/docs/examples" "$DEMO"

python3 - "$DEMO/codexbridger/config.json" <<'PY'
import json, sys

path = sys.argv[1]
config = json.load(open(path))
provider = config["providers"][0]
provider["id"] = "provider"
provider["name"] = "新提供商"
provider["baseURL"] = "http://127.0.0.1:8000/v1"
provider["bearerToken"] = ""
provider["requiresOpenAIAuth"] = False
# Keep the other keys as-is. The synthesized decoder requires every key the app writes,
# so a file with keys removed does not load at all.
provider["httpHeaders"] = {}
provider["queryParams"] = {}
model = provider["models"][0]
model["slug"] = "model-1"
model["displayName"] = "Model 1"
model["modelDescription"] = ""
model["contextWindow"] = 128000
model["maxContextWindow"] = 128000
model["defaultReasoningEffort"] = "medium"
model["supportedReasoningEfforts"] = ["low", "medium", "high"]
provider["models"] = [model]
config["activeProviderID"] = "provider"
config["activeModelSlug"] = "model-1"
config["modelReasoningEffort"] = "xhigh"
with open(path, "w") as handle:
    json.dump(config, handle, indent=2, sort_keys=True)
    handle.write("\n")
print("demo home prepared:", provider["name"], "/", model["slug"])
PY
