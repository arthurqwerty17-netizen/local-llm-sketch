# Release verification

This fork publishes an **unsigned IPA** built by Codemagic from `codemagic.yaml`.
Upstream `Mesutcydev/ios-local-llm` published source-only releases; those
instructions live in its own history and no longer describe what this repository
releases.

## What a build contains

- `LocalLLMSketch.ipa` — an unsigned iOS app archive, packaged from the app
  Codemagic compiled from that commit.
- The workflow prints the IPA's SHA-256 and the app's `CFBundleShortVersionString`
  in its build log, so a download can be checked against the run that made it.

## Install

The IPA is unsigned. Install it with AltStore, SideStore, Sideloadly, or
TrollStore, which re-sign it for your device. The build declares the JIT and
increased-memory entitlements; whether an install keeps them depends on the
signer. The app reports the truth at runtime in Session and in the agent's brief.

## Verify the download

```bash
# from the Codemagic build page, or from a release if publishing is enabled
shasum -a 256 LocalLLMSketch.ipa
```

Every build comes from the workflow in `codemagic.yaml` against a commit of this
repository; the build log names the commit it checked out. If release publishing
is enabled there, the release is tagged `v<marketing version>-<build number>` and
its notes carry the same SHA-256.

## What this does not change

It says nothing about the licenses of the source, the dependencies, or the
separately downloaded models. Review `LICENSE`, `THIRD_PARTY_NOTICES.md`, and
`PROVENANCE.md` before redistribution.
