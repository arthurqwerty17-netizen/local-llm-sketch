# Changelog

This project follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and intends to use semantic version tags for source releases.

## [Unreleased]

### Added

- Live AI activity feed in the Web tab: every browser action the assistant takes
  (navigate, read, desktop mode, download) is shown as it happens, with the real
  URL and outcome. The Web tab comes forward automatically when the model acts,
  and the tab bar shows a live dot while it is working.
- `CapabilityProbe`: the app now tests for executable memory at runtime instead
  of assuming JIT, and reports the result in Session and in the agent's brief.
- JIT and unsigned-executable-memory entitlements in
  `IOSLocalLLM.entitlements`, for sideload signing paths that preserve them.
- `codemagic.yaml`: one Codemagic workflow that builds everything the IPA needs —
  pinned submodules, `llama.xcframework`, XcodeGen, CocoaPods, compile, package —
  and prints the IPA's SHA-256 and version in its log.
- `scripts/build_native_frameworks.sh --skip-whisper` for CI, which does not
  link whisper.cpp.

### Changed

- The app is compiled by Codemagic from `codemagic.yaml` instead of by a GitHub
  Actions macOS job. `.github/workflows/build-ipa.yml` is gone; Actions now runs
  only the free Linux checks, and `github_build` in the app dispatches those.
- README, badges and release docs now describe this fork rather than upstream.

### Removed

- `scorecard.yml`: it fails on this repository and adds nothing to a sideload
  build. `codeql` and `validate` remain.

## [Fork point]

- In-app browser (WKWebView) with a tracker blocklist, smart address bar,
  desktop mode, downloads onto the Files shelf, and a readable page context for
  the assistant.
- Files shelf, viewer, and a small audited shell (`ls`, `cat`, `head`, `wc`,
  `grep`, `swift`, `git`).
- GitHub support: token in the Keychain, repository linking, tree and file
  reads, single-file commits, workflow dispatch, runs and releases.
- Assistant tools for the browser, the shelf, the shell, and GitHub, plus an
  environment brief that tells the model what is wired and what cannot work
  on iOS (no VM, no compiler, no fork/exec).
- Chat / Web / Files tabs under the header.
- Silver, Monochrome, and Electric accents.
- `Build IPA` workflow: parses every Swift source on each push, then archives
  and releases an unsigned IPA where the native frameworks are present.

### Added

- Browsing agent: a multi-page web reader that searches, opens pages, follows
  the most relevant same-site links, sanitizes what it reads, and returns one
  cited evidence block. Available from the new Web screen and as the
  `web_browse` assistant tool. Deterministic by default; the model can drive the
  steps when a backend is wired.
- Session screen with keep-awake modes: off, screen on, and screen plus a
  coarse background location session that keeps a long generation or the local
  API node alive with the screen off. Leases are shared with the local API
  server's existing keep-awake switch.
- Page canvas tint (Neutral, Lavender, Plum, Midnight) alongside the accent
  picker.
- Plum, Orchid, and Lilac accent palettes; Plum is the new default accent.
- `LASLogoMark`: a new minimal purple vector mark used by the header, the
  onboarding, and the splash.

### Changed

- The product is now **Local LLM Sketch** in the app name, bundle display
  name, header wordmark, onboarding, and model-import copy. The repository slug
  and the `OnDeviceLAS` Xcode target name are unchanged.
- The local API server's idle-timer handling moved into `KeepAwakeService`, so
  two features can hold the app awake without cancelling each other.

### Security

- The background keep-alive requests `whenInUse` location at
  three-kilometer accuracy only, stores no coordinate, and starts only when the
  user selects Screen + background. Fetched pages stay subject to the existing
  SSRF validator, robots policy, sanitizer, and token budget.

## [3.2.6] - 2026-07-29

### Added

- OpenSSF Scorecard analysis with public results and code-scanning upload.
- Reproducible source-release archives with SHA-256 checksums and
  GitHub/Sigstore provenance attestations.
- Release verification instructions for contributors and downstream users.

## [3.2.5] - 2026-07-29

### Added

- Open-source governance, provenance, validation, security-model, citation,
  SBOM, and coding-agent documentation.
- Reproducible root-level llama.cpp and whisper.cpp framework build tooling.
- Standalone licensing and notices for VoiceAgentOrb.

### Changed

- Repository identity standardized as `ios-local-llm`.
- Dependency lockfiles synchronized.
- Qwen3 license metadata corrected to Apache-2.0.
- Privacy and network disclosures aligned across repository and in-app text.

### Security

- Added high-confidence Clang warnings and static analyzer checks.
- Expanded responsible disclosure and repository validation guidance.

[Unreleased]: https://github.com/arthurdcosta311-sketch/local-llm-sketch/commits/main
[3.2.6]: https://github.com/Mesutcydev/ios-local-llm/releases/tag/v3.2.6
[3.2.5]: https://github.com/Mesutcydev/ios-local-llm/releases/tag/v3.2.5
