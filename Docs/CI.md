# CI on this repository

## What was wrong

Every job stopped before its first step with:

```
The job was not started because recent account payments have failed
or your spending limit needs to be increased.
```

The newest macOS arm64 images (`macos-15`, `macos-latest`) are the most
contended and are refused/queued first, so the fix is to ask for an older image.

**All macOS jobs now target `macos-14`**, which schedules far more reliably and
still ships an Xcode with the iOS 18 SDK this app needs. The build job also
takes a `runner` input, so a manual run can pick `macos-15` when that is the one
with capacity.

If a run still refuses to start, the account itself has no Actions capacity
left — see *If it still will not start* at the bottom.

## What changed here

The workflow set was cut down so a push spends as little as possible:

| Workflow | Runner | Trigger | Billable |
| --- | --- | --- | --- |
| `validate.yml` → repository | ubuntu | push, PR | no |
| `validate.yml` → swift-syntax | ubuntu (`swift:5.10`) | push, PR | no |
| `dco.yml`, `dependency-review.yml` | ubuntu | PR | no |
| `source-release.yml` | ubuntu | version tag | no |
| `scorecard.yml` | ubuntu | manual | no |
| `codeql.yml` | **macos-14** | weekly cron, manual | yes |
| `packages.yml` | **macos-14** | manual | yes |
| **`build-ipa.yml`** | **macos-14** (input can raise it) | push to `main`/`preview`, manual | **yes** |

Before: four macOS jobs fired on every push (two in `build-ipa.yml`, plus
`codeql.yml` and the VoiceAgentOrb tests inside `validate.yml`). One artifact
now costs one macOS job.

`validate.yml` also gained a free Swift **parse** job: a `swift:5.10` container
parses every source file. It cannot type-check UIKit, SwiftUI or WebKit, but it
catches syntax errors, which otherwise only surface after a full macOS archive.

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

`swift-syntax` proves every file **parses**. It cannot prove that a symbol
exists, that argument labels match, that an `import` resolves (UIKit, SwiftUI
and WebKit are Apple-only), or that the Xcode project references every file —
`project.yml` and `xcodegen` own that last part. Those only fail in a real macOS
archive, which is exactly why that one job exists.

## If it still will not start

The start refusal names billing explicitly. If `macos-14` is refused too, the
account has no Actions capacity for macOS at all, and no workflow change can
get around that. Two things work regardless:

- **Make the repository public.** Public repositories get free macOS minutes.
- **Build on a Mac you own.** The commands are above.
