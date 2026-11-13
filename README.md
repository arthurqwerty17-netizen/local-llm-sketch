# Local LLM Sketch

**Run open-source LLMs on iPhone — offline — and watch the assistant browse.**
A sideload-only fork of [OnDevice LLM](https://github.com/Mesutcydev/ios-local-llm)
with an in-app browser the model can drive, a Files shelf it can read and write,
GitHub commit and CI dispatch, and a purple-first theme.

[![Build IPA](https://github.com/arthurdcosta311-sketch/local-llm-sketch/actions/workflows/build-ipa.yml/badge.svg)](https://github.com/arthurdcosta311-sketch/local-llm-sketch/actions/workflows/build-ipa.yml)
[![Validate](https://github.com/arthurdcosta311-sketch/local-llm-sketch/actions/workflows/validate.yml/badge.svg)](https://github.com/arthurdcosta311-sketch/local-llm-sketch/actions/workflows/validate.yml)
[![License: MIT](https://img.shields.io/badge/original%20code-MIT-2ea44f.svg)](LICENSE)

> Sideload-only build. Not distributed through the App Store, and not affiliated
> with or endorsed by Apple Inc.

## Install

Download `LocalLLMSketch.ipa` from
[Releases](https://github.com/arthurdcosta311-sketch/local-llm-sketch/releases)
and sideload it with AltStore, SideStore, Sideloadly, or TrollStore. It is
unsigned and carries the JIT and increased-memory entitlements. See
[release verification](Docs/RELEASE_VERIFICATION.md) for what a release contains
and how to check it.

CI produces it: `Build IPA` checks out the submodules, builds
`llama.xcframework`, runs `xcodegen generate` and `pod install`, archives,
packages the IPA, and attaches it to a release tagged `v<version>-<build>`.
Every push to `main` builds, so "did it compile?" is a question the Actions tab
answers.

## What the assistant can do here

Everything below is a real tool, and the model is told about it — with live state
such as "a page is open", "a repository is linked", "these files are on the
shelf" — at the start of every turn:

- **Browser** — `browser_read`, `browser_navigate`, `browser_desktop_mode`,
  `browser_download`. These drive the tab you are looking at, and the Web tab
  shows a live trace of each step as it happens. Web Access must be allowed.
- **Files shelf** — `files_list`, `files_read`, `files_write`. Downloads,
  imports and anything the model writes land here, and it can read all of it.
- **Shell** — `shell` runs an audited command set against the shelf: `ls`,
  `cat`, `head`, `wc`, `grep`, `swift`, `git`. Not a general shell: iOS has no
  `fork`/`exec`, so no compilers or package managers on device.
- **GitHub** — `github_repo_files`, `github_read`, `github_commit`,
  `github_build`, `github_runs`. A personal access token with `repo` scope is
  kept in the Keychain, never in preferences.
- **Web search and browsing agent** — `web_search` and `web_browse` search,
  fetch, sanitize for prompt injection, rerank, and compress to a token budget.

### What it deliberately does not claim

The model is told these limits up front so it does not promise otherwise:

- **No virtual machine.** There is no Arch or Debian image here. The build is
  sideload-only and carries the JIT entitlement, and the app probes for
  executable memory at runtime and reports the result in Session — but JIT is a
  prerequisite for an emulator, not an emulator, and there is no hypervisor.
- **No on-device compiler or git binary.** `swift file.swift` runs structural
  checks and says so; real builds and real commits go through GitHub.
- **No extension bridge.** The browser does not run Chrome or Firefox
  extensions.

## The three tabs

**Chat** — the server dashboard: model runtime, API key, endpoints, device
health, parser card.

**Web** — a WKWebView with a content-rule tracker blocklist, a smart address
bar, desktop mode, downloads onto the shelf, and the live AI activity strip.

**Files** — the shelf, with a viewer, a shell panel, and the GitHub controls.

## Theme

Four appearances (System, Light, Dark, OLED), and accents including **Plum**
(the default), Orchid, Lilac, Silver, Monochrome and Electric, plus four page
canvases. The canvas tints only the page fill, so ink contrast and the semantic
red/amber/green never move; OLED keeps its true-black page and locks the canvas.

The mark is drawn in code (`IOSLocalLLM/LASLogoMark.swift`): a purple tile, one
stroked sketch gesture, one dot. Matching export source in
`Docs/Images/local-llm-sketch-mark.svg`.

## Keeping a session awake

Session (the bolt in the header) sets how long the app may run: off, screen on,
or screen plus a coarse background location session for long generations. The
location session requests three-kilometer accuracy and discards every update —
no coordinate is stored, logged, or sent.

## Build locally

```bash
git clone --recurse-submodules https://github.com/arthurdcosta311-sketch/local-llm-sketch.git
cd local-llm-sketch
brew install xcodegen cocoapods cmake
./scripts/build_native_frameworks.sh     # add --skip-whisper to save time
xcodegen generate
pod install
open OnDeviceLAS.xcworkspace
```

The Xcode target is still named `OnDeviceLAS` so the generated project and
schemes keep working.

## Inherited source

This fork keeps the upstream engine: MLX, llama.cpp and Core ML inference, the
[OI]/Anthropic/Ollama-compatible local API, the Mac bridge, voice and vision. For
its internals see:

- `AGENTS.md` — architecture, commands, constraints
- `ARCHITECTURE.md` — system layers and invariants
- `llms.txt` — capability index
- `Docs/REUSABLE_COMPONENTS.md` — what can be lifted out, and how

`project.yml` is the Xcode project source of truth. Never commit model weights,
credentials, signing files, or generated frameworks.

## License

Original project code and documentation are MIT (`LICENSE`). Forked from
OnDevice LLM by Mesut. Third-party code, data and models keep their own terms;
see `THIRD_PARTY_NOTICES.md` and `TRADEMARKS.md`.
