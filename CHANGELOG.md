# Changelog

This project follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and intends to use semantic version tags for source releases.

## [Unreleased]

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

[Unreleased]: https://github.com/Mesutcydev/ios-local-llm/compare/v3.2.6...HEAD
[3.2.6]: https://github.com/Mesutcydev/ios-local-llm/releases/tag/v3.2.6
[3.2.5]: https://github.com/Mesutcydev/ios-local-llm/releases/tag/v3.2.5
