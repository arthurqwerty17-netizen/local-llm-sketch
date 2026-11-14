# CI on this repository

## What the logs actually say

Two different things were happening, and they need different fixes.

**The two `ubuntu-latest` jobs** (`validate.yml` → `repository` and `parse`)
failed in about one second each, before running a single step:

```
The job was not started because recent account payments have failed
or your spending limit needs to be increased.
```

That message is an **account-level Actions block**. It cannot come from macOS
capacity, because neither job asks for a macOS runner: they are free Linux jobs.
While it is in place, *every* job on this account is refused — Linux included —
so nothing in this repository is being compiled or tested at all.

**The macOS `build` job** is the separate case. It sat in `queued`, which is what
a job does when it is waiting for a runner rather than being refused. Two things
can cause that, and both were true here:

1. **The label it asked for no longer exists.** The workflow was moved to
   `macos-13` by an earlier "use an older image" change, but GitHub had already
   retired macOS 13, so `macos-13` is not in the `actions/runner-images`
   catalogue. The change before that had used `macos-14`, which was retired on
   **2026-11-02** — also gone. A job asking for a retired label is never picked
   up: it waits in `queued` indefinitely. Both attempts to pick a safer older
   image were pointing at images that no longer existed.
2. **Standard macOS runners are contended.** Standard arm64 images queue behind
   larger runners under load, which is the effect named in the original report.
   That is a real cost of the standard pool, but it is a delay, not a refusal.

## Runner images that exist right now

From `actions/runner-images` (its README is the authority; a label is only real
if it is listed there):

| Label | Arch | State |
| --- | --- | --- |
| `macos-15` | arm64 | GA — **the default here** |
| `macos-15-intel` | x64 | GA, the other pool |
| `macos-26` / `macos-latest` | arm64 | GA, newest |
| `xcode-27` | arm64 | preview |
| `macos-14` | — | **removed 2026-11-02**; the previous default here |
| `macos-13` | — | **removed earlier**; the default before that |

`macos-14` is listed as **x64**, not arm64 — the old arm64 `macos-14` label is
gone, which is why an earlier note about an unsupported `macos-14-arm64-us-xl`
configuration was misleading. Do not assume an image's architecture from its
version; check the table.

## What changed here

- **`build-ipa.yml` defaults to `macos-15`** (arm64, GA) instead of the removed
  `macos-13`.
- **A `runner` dropdown** on manual dispatch offers `macos-15`, `macos-26` and
  `macos-15-intel`, so a run can move to whichever live image schedules without
  editing the file. Pushes use `macos-15`.
- `codeql.yml`, `packages.yml` and `runner-probe.yml` were moved off `macos-14`
  (retired 2026-11-02) to labels that still exist.
- The workflow set stays as small as it can be: one billable job for the
  artifact, and free Linux jobs for everything else.

| Workflow | Runner | Trigger | Billable |
| --- | --- | --- | --- |
| `validate.yml` → `repository` | ubuntu | push, PR | no |
| `validate.yml` → `parse` | ubuntu, `swift:6.0` container | push, PR | no |
| `dco.yml`, `dependency-review.yml` | ubuntu | PR | no |
| `source-release.yml` | ubuntu | version tag | no |
| `scorecard.yml` | ubuntu | manual | no |
| `codeql.yml` | `macos-15` | weekly cron, manual | yes |
| `packages.yml` | `macos-15` | manual | yes |
| **`build-ipa.yml`** | **`macos-15`** (dropdown can raise it) | push to `main`/`preview`, manual | **yes** |

## Why an image change alone will not produce an IPA

The billing refusal above is not about macOS. Until it is cleared, the Linux
jobs fail too, so no workflow can run at all — and a queue position cannot fix a
refused job. Both halves have to be true for a build to happen: **an account
with Actions capacity, and a runner label that still exists.** The second half is
now fixed here; the first is not something a workflow can change.

## Getting an IPA out

Pick one.

### 1. Make the repository public — free, and the shortest path

**Actions is free for public repositories**, macOS runners included. Nothing in
this tree is secret: it is a fork of an MIT-licensed open-source project, and
`scripts/validate_open_source.sh` fails the build if a credential, IPA,
provisioning profile or model weight is ever committed.

**Settings → General → Danger Zone → Change visibility → Make public**, then
push to `main` or open **Actions → Build IPA → Run workflow**. The IPA appears
on the Releases page, tagged `v<version>-<build>`.

### 2. Add billing for private macOS minutes

**Settings → Billing and plans** → add a payment method or raise the spending
limit, then run **Actions → Build IPA → Run workflow**.

### 3. Build it on your own Mac

On any Apple-silicon Mac:

```bash
git clone --recurse-submodules https://github.com/arthurdcosta311-sketch/local-llm-sketch.git
cd local-llm-sketch
brew install xcodegen cocoapods cmake
./scripts/build_native_frameworks.sh --skip-whisper
xcodegen generate && pod install
xcodebuild -workspace OnDeviceLAS.xcworkspace -scheme OnDeviceLAS \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/LocalLLMSketch.xcarchive archive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
mkdir -p Payload
cp -R build/LocalLLMSketch.xcarchive/Products/Applications/*.app Payload/
zip -qry LocalLLMSketch.ipa Payload
```

## What the free check proves, and what it does not

The `parse` job proves every file **parses**. It cannot prove that a symbol
exists, that argument labels match, that an `import` resolves (UIKit, SwiftUI
and WebKit are Apple-only), or that the Xcode project references every file —
`project.yml` and `xcodegen` own that last part. Those only fail in a real macOS
archive, which is exactly why that one job exists.

## If the build job stays queued

Try, in order:

1. **Run workflow** with `runner` set to `macos-15-intel` — a different pool, and
   the artifact is identical (device slices are arm64 either way).
2. **Run workflow** with `runner` set to `macos-26`.
3. Wait — standard macOS runners drain in cycles; a queued job usually starts
   eventually unless the label is retired.

If a job fails in about a second instead of waiting, it is the billing block, not
the runner.

## Verified build — 2026-11-14

The tree was compiled for the first time on a remote Mac (Xcode 27.1, arm64):

- `xcodegen generate` and `pod install` succeed.
- `xcodebuild build -configuration Debug -destination 'generic/platform=iOS Simulator'` — **succeeds**.
- `xcodebuild build -configuration Release -destination 'generic/platform=iOS'` — **succeeds**;
  the unsigned `OnDeviceLAS.app` packages into a 29 MB IPA.
- `xcodebuild archive` fails *on that particular machine* with
  `unable to spawn process '/usr/sbin/chown' (Operation not permitted)` from
  SwiftPM targets. That is a sandbox restriction of the remote build host, not of
  the project; GitHub's own runners have no such restriction, so `Build IPA`
  archives normally there.

On a similarly restricted host, use `build` plus a manual `Payload/` zip instead
of `archive`:

```bash
xcodebuild -workspace OnDeviceLAS.xcworkspace -scheme OnDeviceLAS \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath build/dd build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
mkdir -p Payload && cp -R build/dd/Build/Products/Release-iphoneos/*.app Payload/
zip -qry LocalLLMSketch.ipa Payload
```

Six compile errors were fixed to get there: `Result<_, String>` (String is not
an `Error`), a nonisolated read of MainActor state, a missing `ObservedObject`,
and llama.cpp's new `llama_sampler_init_penalties` signature.
