#!/usr/bin/env python3
"""Auto-discover the minimal valid entry for Codex model_catalog_json.

Loop: write candidate, run codex debug models, read the serde error
('missing field X' / 'invalid type'), add a sensible default for X, repeat.
The converged entry is the hardened static fallback template.
"""
import json
import os
import pathlib
import re
import shutil
import subprocess

NL = chr(10)
CODEX = "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
ROOT = pathlib.Path("/tmp/codexdiscover")

DEFAULTS = {
    "slug": "probe-model-a",
    "display_name": "Probe A",
    "description": "probe",
    "supported_reasoning_levels": [{"effort": "low", "description": "fast"}, {"effort": "medium", "description": "balanced"}, {"effort": "high", "description": "deep"}],
    "default_reasoning_level": "medium",
    "shell_type": "shell_command",
    "visibility": "list",
    "supported_in_api": True,
    "priority": 1,
    "context_window": 128000,
    "max_context_window": 128000,
    "effective_context_window_percent": 95,
    "base_instructions": "You are a coding agent.",
    "model_messages": {"instructions_template": "You are a coding agent."},
    "supports_reasoning_summaries": True,
    "default_reasoning_summary": "none",
    "support_verbosity": True,
    "default_verbosity": "low",
    "apply_patch_tool_type": "freeform",
    "web_search_tool_type": "text_and_image",
    "truncation_policy": {"mode": "tokens", "limit": 10000},
    "supports_parallel_tool_calls": True,
    "supports_image_detail_original": True,
    "supports_search_tool": False,
    "experimental_supported_tools": [],
    "input_modalities": ["text"],
    "additional_speed_tiers": [],
    "service_tiers": [],
    "availability_nux": None,
    "upgrade": None,
}


def run(home):
    env = dict(os.environ, CODEX_HOME=str(home))
    p = subprocess.run([CODEX, "debug", "models"], capture_output=True, text=True, env=env)
    err = NL.join(l for l in (p.stderr or "").splitlines() if "PATH aliases" not in l).strip()
    return p.returncode, p.stdout or '', err


def attempt(entry, tag):
    home = ROOT / tag
    shutil.rmtree(home, ignore_errors=True)
    catdir = home / "model-catalogs"
    catdir.mkdir(parents=True)
    catfile = catdir / "probe-model-catalog.json"
    catfile.write_text(json.dumps({"models": [entry]}, indent=2))
    (home / "config.toml").write_text(NL.join([
        "model_provider = " + json.dumps("probe"),
        "model = " + json.dumps("probe-model-a"),
        "model_catalog_json = " + json.dumps(str(catfile)),
        "",
        "[model_providers.probe]",
        "name = " + json.dumps("Probe"),
        "base_url = " + json.dumps("http://127.0.0.1:1/v1"),
        "wire_api = " + json.dumps("responses"),
        "",
    ]))
    return run(home)


def main():
    shutil.rmtree(ROOT, ignore_errors=True)
    ROOT.mkdir(parents=True)
    entry = {"slug": "probe-model-a"}
    added = []
    for step in range(40):
        rc, out, err = attempt(entry, "step%02d" % step)
        if rc == 0:
            print("CONVERGED after %d additions" % len(added))
            print("added fields in order: " + ", ".join(added))
            print("--- accepted minimal entry ---")
            print(json.dumps(entry, indent=2)[:2000])
            data = json.loads(out)
            ms = data.get("models", [])
            print("--- CLI reports %d model(s): %s" % (len(ms), [m.get("slug") for m in ms]))
            return
        if "missing both `base_instructions` and" in err:
            if "base_instructions" not in entry:
                entry["base_instructions"] = DEFAULTS["base_instructions"]
                added.append("base_instructions")
                print("step %d: + base_instructions (custom error)" % step)
                continue
        m = re.search(r"missing field `([^`]+)`", err)
        if not m:
            print("STEP %d non-missing-field error:" % step)
            print("   " + err.replace(NL, " | ")[:400])
            return
        field = m.group(1)
        if field not in DEFAULTS:
            print("STEP %d needs unknown field %s: %s" % (step, field, err[:200]))
            return
        entry[field] = DEFAULTS[field]
        added.append(field)
        print("step %d: + %s" % (step, field))
    print("did not converge")


if __name__ == "__main__":
    main()