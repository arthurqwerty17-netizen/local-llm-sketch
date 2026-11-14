# CI on this repository

## Where the app is built

The IPA is compiled by **Codemagic**, not by GitHub Actions. `codemagic.yaml` at
the repository root holds the whole build, and there is no macOS workflow here
any more: `.github/workflows/build-ipa.yml` was removed after every attempt on
this account was refused for billing and, when it did schedule, spent half an
hour on a runner whose Archive step failed for reasons unrelated to the code.

What GitHub Actions still does is the free half:

| Workflow | Runner | Trigger | Billable |
| --- | --- | --- | --- |
| `validate.yml` → `repository` | ubuntu | push, PR | no |
| `validate.yml` → `parse` | ubuntu, `swift:6.0` container | push, PR | no |
| `dco.yml`, `dependency-review.yml` | ubuntu | PR | no |
| `source-release.yml` | ubuntu | version tag | no |
| `scorecard.yml` | ubuntu | manual | no |
| `codeql.yml` | `macos-15` | weekly cron, manual | yes |
| `packages.yml` | `macos-15` | manual | yes |

## Codemagic, once

1. Sign in at [codemagic.io](https://codemagic.io) with the GitHub account that
   owns this repository.
2. **Applications → Add application**, pick `local-llm-sketch`, and let Codemagic
   read `codemagic.yaml` from it. Nothing else has to be configured: the file
   names its own machine (`mac_mini_m2`), Xcode version (`latest`), steps and
   artifact.
3. Press **Start new build**. The IPA appears under the build's artifacts, and
   the log prints its SHA-256 and the app's marketing version.

`max_build_duration` is 120 minutes, which is generous: the llama.cpp
XCFramework is the slow part, and Codemagic caches nothing between builds here.

To publish the IPA as a GitHub Release instead of a build artifact, connect
GitHub under **Team → Integrations**, then uncomment the `publishing` block at
the bottom of `codemagic.yaml`.

To build on every push rather than on demand, uncomment its `triggering` block.

## What the steps do, and why in that order

1. **Install dependencies** — `cmake` and `xcodegen` through Homebrew, CocoaPods
   through RubyGems if the image has no `pod`.
2. **Fetch submodules** — llama.cpp and whisper.cpp are gitlinks.
3. **Build llama.cpp** — `scripts/build_native_frameworks.sh --skip-whisper`
   produces `ThirdParty/llama.cpp/build-apple/llama.xcframework`. The server
   target does not link whisper.cpp, so its slice is skipped.
4. **Generate the workspace** — `xcodegen generate` from `project.yml`, then
   `pod install`.
5. **Compile** — `xcodebuild build`, not `archive`. An unsigned sideload IPA
   needs no archive, and `build` succeeds on hosts where `archive` fails on
   SwiftPM file ownership.
6. **Package** — `Payload/` plus `zip` into `LocalLLMSketch.ipa`.

## If a build fails

Read the step's log in Codemagic. The two failures seen so far:

- **`error: GitHub Actions must be pinned to full commit SHAs`** — that is the
  `validate` job, not the build; every `uses:` must carry a 40-character SHA.
- **A Swift compile error at the Compile step** — a real code error. The `parse`
  job in `validate.yml` catches syntax only; type errors and missing symbols
  only appear here.

## Verified build — 2026-11-14

The tree was compiled on a remote Mac (Xcode 27.1, arm64) with the same steps
Codemagic runs:

- `xcodegen generate` and `pod install` succeed.
- `xcodebuild build -configuration Debug -destination 'generic/platform=iOS Simulator'` — **succeeds**.
- `xcodebuild build -configuration Release -destination 'generic/platform=iOS'` — **succeeds**;
  the unsigned `OnDeviceLAS.app` packages into a 29 MB IPA.
- `xcodebuild archive` fails *on that particular machine* with
  `unable to spawn process '/usr/sbin/chown' (Operation not permitted)` from
  SwiftPM targets. That is a sandbox restriction of that host, which is why
  `codemagic.yaml` builds rather than archives.

The same commands by hand:

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
and llama.cpp's `llama_sampler_init_penalties` signature.

## What the free check proves, and what it does not

The `parse` job proves every file **parses**. It cannot prove that a symbol
exists, that argument labels match, that an `import` resolves (UIKit, SwiftUI
and WebKit are Apple-only), or that the Xcode project references every file —
`project.yml` and `xcodegen` own that last part. Those only fail in a real macOS
build, which is exactly why Codemagic's Compile step exists.

## The llama.cpp pin decides the sampler signature

`ThirdParty/llama.cpp` is a submodule gitlink pinned to
`7ef790f90a4772eadd6966815f6d3ae7d93c7e03`, and every build compiles exactly that
revision. At that pin `llama_sampler_init_penalties` takes four arguments —
`(penalty_last_n, penalty_repeat, penalty_freq, penalty_present)` — so
`LlamaCppBridge.makeSampler` calls it that way. Newer llama.cpp revisions
insert the vocabulary size as the first argument; building against such a
revision without updating the call is a compile error, and building HEAD by hand
is what hid the difference until CI hit the Archive step. When the submodule is
bumped, change that one call and let a build confirm it.
