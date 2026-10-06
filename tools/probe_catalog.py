#!/usr/bin/env python3
"""Discover the exact contract of Codex model_catalog_json.

Feedback loop: write a candidate catalog into a throwaway CODEX_HOME and run
codex debug models. Codex validates the catalog with serde, so every missing or
malformed field comes back as a precise error.
"""
import json
import os
import pathlib
import shutil
import subprocess

NL = chr(10)
CODEX = "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
ROOT = pathlib.Path("/tmp/codexcatalog2")
INSTR = "You are a probe agent."


def levels(efforts=('low', 'medium', 'high')):
    return [{"effort": e, "description": "level " + e} for e in efforts]


def run(home, args):
    env = dict(os.environ, CODEX_HOME=str(home))
    p = subprocess.run([CODEX] + args, capture_output=True, text=True, env=env)
    err = NL.join(l for l in (p.stderr or "").splitlines() if "PATH aliases" not in l).strip()
    return p.returncode, p.stdout or '', err


def probe(name, catalog):
    home = ROOT / name
    shutil.rmtree(home, ignore_errors=True)
    catdir = home / "model-catalogs"
    catdir.mkdir(parents=True)
    catfile = catdir / "probe-model-catalog.json"
    catfile.write_text(json.dumps(catalog, indent=2))
    cfg = [
        "model_provider = " + json.dumps("probe"),
        "model = " + json.dumps("probe-model-a"),
        "model_catalog_json = " + json.dumps(str(catfile)),
        "",
        "[model_providers.probe]",
        "name = " + json.dumps("Probe"),
        "base_url = " + json.dumps("http://127.0.0.1:1/v1"),
        "wire_api = " + json.dumps("responses"),
        "",
    ]
    (home / "config.toml").write_text(NL.join(cfg))
    rc, out, err = run(home, ["debug", "models"])
    status = "LOADED" if rc == 0 else "REJECTED"
    print("--- %s: %s" % (name, status))
    if err:
        print("    ERR: " + err.replace(NL, " | ")[:260])
    if rc == 0 and out.strip():
        data = json.loads(out)
        models = data.get("models", [])
        print("    models=%d slugs=%s" % (len(models), [m.get("slug") for m in models][:12]))
        for m in models:
            if m.get("slug") == "probe-model-a":
                print("    a: ctx=%s max=%s efforts=%s vis=%s prio=%s" % (
                    m.get("context_window"), m.get("max_context_window"),
                    [x.get("effort") for x in m.get("supported_reasoning_levels", [])],
                    m.get("visibility"), m.get("priority")))


def main():
    shutil.rmtree(ROOT, ignore_errors=True)
    ROOT.mkdir(parents=True)

    minimal = {"slug": "probe-model-a", "display_name": "Probe A",
               "supported_reasoning_levels": levels(), "base_instructions": INSTR}
    probe("minimal_base_instructions", {"models": [minimal]})

    minimal_msgs = {"slug": "probe-model-a", "display_name": "Probe A",
                    "supported_reasoning_levels": levels(),
                    "model_messages": {"instructions_template": INSTR}}
    probe("minimal_model_messages", {"models": [minimal_msgs]})

    rich = dict(minimal)
    rich.update({"context_window": 200000, "max_context_window": 200000,
                 "description": "probe", "default_reasoning_level": "high",
                 "visibility": "list", "supported_in_api": True, "priority": 7,
                 "supports_reasoning_summaries": True,
                 "default_reasoning_summary": "none",
                 "shell_type": "shell_command", "apply_patch_tool_type": "freeform"})
    probe("rich_two_models", {"models": [rich, dict(rich, slug="probe-model-b", display_name="Probe B",
                                                  context_window=64000, max_context_window=64000,
                                                  supported_reasoning_levels=levels(("low", "high"))) ]})


if __name__ == "__main__":
    main()