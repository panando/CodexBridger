#!/usr/bin/env python3
"""Probe how the real Codex CLI (ChatGPT.app bundle) validates config.toml fields.

Codex tolerates unknown keys, so the only reliable discriminator for "is this a
supported field" is a TOML type mismatch: known fields are typed and fail to
deserialize, unknown fields are silently ignored.
"""
import os
import pathlib
import shutil
import subprocess
import sys

CODEX = "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"

BASE = """model_provider = "t"
model = "m"

[model_providers.t]
name = "T"
base_url = "http://127.0.0.1:1/v1"
wire_api = "responses"
"""

INVALID_TOML = """model_provider = "t"
[[[ bad toml
"""

CASES = {
    "A_invalid_toml_syntax": INVALID_TOML,
    "B_provider_name_int": BASE.replace('name = "T"', "name = 123"),
    "C_provider_bogus_field": BASE + 'bogus_xyz = 5',
    "D_provider_http_headers_int": BASE + "http_headers = 123",
    "E_provider_query_params_int": BASE + "query_params = 123",
    "F_provider_requires_openai_auth_str": BASE + 'requires_openai_auth = "nope"',
    "G_provider_model_catalog_url_int": BASE + "model_catalog_url = 123",
    "H_provider_request_max_retries_str": BASE + 'request_max_retries = "x"',
    "I_top_model_context_window_str": 'model_context_window = "abc"\n' + BASE,
    "J_top_model_max_output_tokens_str": 'model_max_output_tokens = "abc"\n' + BASE,
    "K_top_disable_response_storage_str": 'disable_response_storage = "abc"\n' + BASE,
    "L_top_bogus_key": "totally_bogus_top_xyz = 1\n" + BASE,
    "M_top_bad_reasoning_effort": 'model_reasoning_effort = "bogus_effort"\n' + BASE,
    "N_top_bad_reasoning_summary": 'model_reasoning_summary = "bogus_summary"\n' + BASE,
    "O_top_bad_verbosity": 'model_verbosity = "bogus_verbosity"\n' + BASE,
    "P_provider_bad_wire_api": BASE.replace('wire_api = "responses"', 'wire_api = "bogus_api"'),
    "Q_clean_baseline": BASE,
}


def run(home, args):
    env = dict(os.environ, CODEX_HOME=str(home))
    p = subprocess.run([CODEX] + args, capture_output=True, text=True, env=env)
    err = "\n".join(
        line for line in (p.stderr or "").splitlines() if "PATH aliases" not in line
    ).strip()
    return p.returncode, len(p.stdout or ""), err


def main():
    base = pathlib.Path("/tmp/codexprobe")
    shutil.rmtree(base, ignore_errors=True)
    results = []
    for name, toml in sorted(CASES.items()):
        home = base / name
        home.mkdir(parents=True)
        (home / "config.toml").write_text(toml)
        rc, out_bytes, err = run(home, ["debug", "models"])
        results.append((name, rc, out_bytes, err))
        flag = "ERROR" if (rc != 0 or err) else "ok"
        print("%-42s rc=%s stdout=%7dB  %s" % (name, rc, out_bytes, flag))
        if err:
            print("     " + err.replace("\n", " | ")[:360])
    print()
    print("summary: %d cases, %d produced an error" % (
        len(results), sum(1 for r in results if r[1] != 0 or r[3])))


if __name__ == "__main__":
    sys.exit(main())
