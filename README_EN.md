<div align="center">

# CodexBridger

<img src="CodexBridger.png" alt="CodexBridger" width="128">

**Bring any third-party model provider into ChatGPT / Codex — no more hand-editing config files.**

CodexBridger is a macOS app. Fill in a provider address, an API key and a list of models, press **Activate**, and it writes the files ChatGPT (Codex) actually reads. Open ChatGPT and your provider is ready to use.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![macOS 14.0+](https://img.shields.io/badge/macOS-14.0%2B-black?logo=apple)](https://www.apple.com/macos/)
[![Swift 6.0+](https://img.shields.io/badge/Swift-6.0%2B-orange?logo=swift)](https://swift.org)

[Install](#install) ·
[Usage](#usage) ·
[Features](#features) ·
[Safety](#how-it-avoids-breaking-your-configuration)

[简体中文](./README.md) · **English**

</div>

---

<p align="center">
  <a href="ScreenShot2.png"><img src="ScreenShot2.png" alt="CodexBridger main window: providers on the left, provider details, credentials and models on the right" width="760"></a>
</p>

## What's new in 1.3.0 - Auto-review model

Not every third-party model can run Codex's auto-approval reviewer - the reviewer sub-agent needs a strict JSON-schema structured output, and some models (or proxies) refuse it. 1.3.0 turns this into a button:

- In the provider page's **Auto-review model** section, click **Run check**. The app sends one minimal Responses request per model and validates the answer the way Codex itself would.
- When the scan finishes, a green note reports how many models passed. The drop-down only lists the passing models; you can type freely too, or fall back to a hand-typed slug.
- The chosen slug is written into the `auto_review_model_override` field of **every** catalog entry under the provider. Codex then uses it as the reviewer model for all of them. Leave it blank to skip the field entirely - Codex falls back to using the active model itself.

<p align="center">
  <img src="auto-review-section.png" alt="Auto-review model: one-click check, completion summary, and an editable combo for the reviewer" width="720">
</p>

Notes on the design: the verdict follows the order of a real Codex harness call (not a completed response, strip markdown fences, not JSON, not an object, wrong keys, bad decision value). Strict schema is sent on the `/responses` wire; if the provider has no Responses endpoint at all, the probe falls back to `/chat/completions` automatically. Results are cached inside this app's own configuration file (**never includes any credential**) and survive a restart; if the model list has changed since the last scan, a "results may be stale" hint appears.

## Why CodexBridger?

Driving ChatGPT with a third-party model (DeepSeek, Kimi, GLM, OpenRouter, …) means editing configuration files by hand. There are three of them, the field names and accepted values matter, and one wrong key can stop ChatGPT from starting — and you are expected to remember to back things up first.

CodexBridger turns that into "fill in a form, press one button": no field names to memorise, no manual backups, and it asks before it displaces whatever is in use.

It does exactly one thing: **generate and maintain ChatGPT's configuration files**. No injection, no process hijacking, and ChatGPT does not need to be running.

## The three files it writes

| File | Location | Purpose |
| --- | --- | --- |
| `config.toml` | `~/.codex/config.toml` | Tells ChatGPT which provider, which model, and where the model parameter file is |
| `auth.json` | `~/.codex/auth.json` | Stores credentials (see below) |
| `<provider>-model-catalog.json` | `~/.codex/model-catalogs/` | Model parameter file |

### How `auth.json` is handled

It is **neither** a blind overwrite **nor** an unconditional merge:

- **Keeps** everything already in the file that is unrelated, such as ChatGPT's own login token.
- **Replaces** `OPENAI_API_KEY` and writes the current provider's `<PROVIDER>_KEY`.
- **Removes** `*_KEY` / `*_API_KEY` entries left behind by other providers, so a retired service's secret does not stay on disk.
- When the bearer token is empty, no credential is written and the interface says so.

### Backup rules

Before anything is replaced, the existing `config.toml` and `auth.json` are copied into `~/.codex/backup/config-backup/`, with the provider they belonged to in the name:

- `config-<provider>-yyyy-mm-dd-hhmm-bak.toml`
- `auth-<provider>-yyyy-mm-dd-hhmm-bak.json`

A second operation within the same minute gets a `-2` or `-3` suffix instead of overwriting the previous copy.

**There is no exception**: every **Activate** backs the current files up first, including when you switch between two providers this app manages. There used to be one — a configuration this app had generated was not backed up — and that left the single action which replaces what ChatGPT reads with no way back, so 1.2.0 removed it. Backups accumulate once per activation; delete them in the backup folder when you like, since the file names carry the provider and the timestamp.

## Install

### Download (recommended)

Download the `.dmg` from [Releases](https://github.com/panando/CodexBridger/releases), open it, and drag CodexBridger into Applications.

### "CodexBridger is damaged and can't be opened"

The current build uses an **ad-hoc signature**. It is not signed with an Apple Developer ID certificate and is not notarized by Apple. Because of this, macOS Gatekeeper may show either of:

> "CodexBridger" is damaged and can't be opened. You should move it to the Trash.

> "CodexBridger" cannot be opened because the developer cannot be verified.

**This usually does not mean the app is actually corrupted.** It means macOS has attached a quarantine flag to a downloaded app that has not been notarized.

#### Option 1: open from System Settings (no terminal)

1. Try opening CodexBridger once.
2. If macOS blocks it, open **System Settings → Privacy & Security**.
3. In the Security section, look for the CodexBridger warning.
4. Click **Open Anyway**.
5. Confirm opening the app.

#### Option 2: fix with Terminal

If "Open Anyway" does not appear, or macOS still says the app is damaged, first drag `CodexBridger.app` into the Applications folder. Then open Terminal and run:

```bash
sudo xattr -dr com.apple.quarantine /Applications/CodexBridger.app
```

Enter your Mac login password and press Enter. Terminal will not show password characters while typing. This is normal. Then open CodexBridger again.

If you are not sure about the app path, type this command with the trailing space:

```bash
sudo xattr -dr com.apple.quarantine 
```

Then drag `CodexBridger.app` from Finder into the Terminal window and press Enter.

> Note: Only do this for apps downloaded from sources you trust.

### Build from source

```bash
git clone https://github.com/panando/CodexBridger.git
cd CodexBridger
./scripts/build-app.sh          # produces build/CodexBridger.app
open build/CodexBridger.app     # launch it
```

Requires macOS 14 or later and the Xcode command line tools. **Zero external dependencies** — the project uses only the system Foundation and SwiftUI, and builds offline.

To hand the app to someone else, build the version that runs on both Apple silicon and Intel (**an arm64-only build does nothing at all when opened on an Intel Mac**):

```bash
./scripts/build-app.sh release universal dmg   # produces build/CodexBridger-<VERSION>.dmg
```

The version has a single source: the `VERSION` file at the repository root. Change it and the build stamps it into the app's About pane. Swapping `dmg` for `zip` produces an archive instead — that needs no disk-arbitration access, so it works in CI.

## Usage

<p align="center">
  <a href="ScreenShot1.png"><img src="ScreenShot1.png" alt="CodexBridger welcome screen shown before any provider is added" width="760"></a>
</p>

Before any provider is added, the window lists what the app can do and offers a **New provider** button.

1. Click **Add** at the bottom left and pick a preset (DeepSeek, Moonshot, MiniMax, Zhipu GLM, OpenRouter) or choose a custom provider.
2. Fill in the **Base URL** and **API key**.
3. Under **Models**, add the models you want. Each one carries its own context window, reasoning effort and so on.
4. Click **Activate** at the bottom right. The app writes the files and reports what it did; if it would displace the provider in use, it asks first. (**Save** only stores the settings inside this app; **Activate** is what writes ChatGPT's files, and it backs them up first.)
5. Open ChatGPT and use it.

## Features

- **Provider management** — create, edit and delete providers; several can coexist and you can switch at any time.
- **Several models per provider** — per-model context window, maximum context, reasoning effort, and whether the model appears in the list.
- **Presets for common providers** — DeepSeek, Moonshot, MiniMax, Zhipu GLM and OpenRouter, plus fully custom providers.
- **Three credential modes** — bearer token, environment variable, or login command. They are mutually exclusive per the official documentation; only the one you choose is written.
- **Model parameter file generation** — uses the model catalogue bundled with your ChatGPT installation as the template, so the generated parameters match your version.
- **Checks before activation** — a persistent warning when `base_url` is empty or points at this machine, and a confirmation dialog before displacing a provider in use.
- **Backup browser** — the settings window lists the backup files already on disk.
- **Global configuration** — the top-level `config.toml` settings (approvals and sandbox, reasoning visibility) are editable here too, each with an ⓘ explanation. They are backed up before writing as well, and a change made by another program stops the write and asks you first.
- **Save and Activate do different jobs** — **Save** writes this app's own settings; **Activate** applies a provider to ChatGPT. For the provider in use with nothing changed, **Activate** is greyed out; saving a change brings it back.

## How it avoids breaking your configuration

1. **Back up before writing.** The backup completes before a single byte is modified, every time.
2. **Atomic writes.** Every file is written to a temporary file and then renamed over the target. If power is lost or the process is killed, ChatGPT sees either the old file or the new one, never half of either.
3. **Only its own keys are touched.** It does not re-serialise the whole `config.toml`; it replaces only the top-level fields it owns and the single `[model_providers.<id>]` table it manages. Your plugins, MCP servers, hooks and skills are left exactly as they were.
4. **Nothing unsupported is written.** Every field comes from the official configuration reference.
5. **It asks before displacing what is in use.** Before activating, it reads which provider ChatGPT is actually using. If the change would move away from a *different* provider, it asks first, stating "currently using X, switching to Y".
6. **A broken file is never reported as "no configuration".** If CodexBridger's own `config.json` is corrupt, the interface reports the error and states that the original file was left untouched, rather than showing "0 providers".

## Known limitations

- Requires macOS 14 or later. The interface is SwiftUI, and there is no Windows version.
- **No Apple Developer signature and no notarisation.** Other people will be blocked the first time they open a downloaded copy. This is not corruption; see ["CodexBridger is damaged and can't be opened"](#codexbridger-is-damaged-and-cant-be-opened).

## License

Released under the [MIT License](LICENSE).

Copyright (c) 2026 panando
