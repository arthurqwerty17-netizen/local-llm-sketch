# Release verification

This fork publishes an **unsigned IPA** built by the `Build IPA` workflow. Upstream
`Mesutcydev/ios-local-llm` published source-only releases; those instructions live
in its own history and no longer describe what this repository releases.

## What a release here contains

- `LocalLLMSketch.ipa` — an unsigned iOS app archive built from the tagged commit.
- The release tag is `v<marketing version>-<build number>`, taken from the built
  app's `Info.plist`, so two builds of the same version never collide.

## Install

The IPA is unsigned. Install it with AltStore, SideStore, Sideloadly, or
TrollStore, which re-sign it for your device. The build declares the JIT and
increased-memory entitlements; whether an install keeps them depends on the
signer. The app reports the truth at runtime in Session and in the agent's brief.

## Verify the download

```bash
gh release download --repo arthurdcosta311-sketch/local-llm-sketch --pattern '*.ipa'
shasum -a 256 LocalLLMSketch.ipa
```

Every release is built by the workflow in this repository from a commit on
`main` or `preview`; the release body names the ref and the SHA.

## What this does not change

It says nothing about the licenses of the source, the dependencies, or the
separately downloaded models. Review `LICENSE`, `THIRD_PARTY_NOTICES.md`, and
`PROVENANCE.md` before redistribution.
