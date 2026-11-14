#!/usr/bin/env bash

# Reproducibly build the native llama.cpp and whisper.cpp XCFrameworks from
# pinned submodules. Generated frameworks remain ignored by Git.

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
include_catalyst=0
skip_whisper=0

for arg in "$@"; do
  case "$arg" in
    --with-catalyst) include_catalyst=1 ;;
    # The OnDeviceLAS target links llama.xcframework only; whisper.cpp is used
    # by voice sources this target excludes. CI passes this to keep the build
    # under the job timeout.
    --skip-whisper)  skip_whisper=1 ;;
    *)
      echo "usage: $0 [--with-catalyst] [--skip-whisper]" >&2
      exit 64
      ;;
  esac
done

git -C "$repository_root" submodule update --init --recursive

llama_root="${repository_root}/ThirdParty/llama.cpp"
llama_patch="${repository_root}/Patches/llama.cpp-ios-only-xcframework.patch"
llama_ios_only=0

if [[ ! -f "${llama_root}/build-xcframework.sh" ]]; then
  echo "error: ThirdParty/llama.cpp is missing; run 'git submodule update --init'" >&2
  exit 1
fi

if grep -q 'IOS_ONLY:-0' "${llama_root}/build-xcframework.sh"; then
  echo "==> llama.cpp iOS-only build support is already present"
  llama_ios_only=1
elif git -C "$llama_root" apply --check "$llama_patch" >/dev/null 2>&1; then
  echo "==> Applying the tracked llama.cpp iOS-only build patch"
  git -C "$llama_root" apply "$llama_patch"
  llama_ios_only=1
else
  # Current llama.cpp takes the slices as arguments instead of an IOS_ONLY
  # switch, so the patch is obsolete there. Ask for the two iOS slices by name;
  # without them the script builds macOS, visionOS and tvOS as well, which
  # triples the build time for a framework this app never links.
  echo "==> The tracked patch does not apply; requesting iOS slices by name"
  llama_ios_only=2
fi

if [[ -e "${llama_root}/build-apple/llama.xcframework" ]]; then
  echo "error: generated llama.xcframework already exists; remove it before rebuilding" >&2
  exit 1
fi
if [[ -e "${repository_root}/ThirdParty/whisper.cpp/build-apple/whisper.xcframework" ]] \
   && [[ "$skip_whisper" == 0 ]]; then
  echo "error: generated whisper.xcframework already exists; remove it before rebuilding" >&2
  exit 1
fi

echo "==> Building llama.cpp iOS XCFramework"
case "$llama_ios_only" in
  2) (cd "$llama_root" && ./build-xcframework.sh ios-sim ios-device) ;;
  *) (cd "$llama_root" && IOS_ONLY=1 ./build-xcframework.sh) ;;
esac

if [[ "$skip_whisper" == 0 ]]; then
  echo "==> Building whisper.cpp iOS XCFramework"
  "${repository_root}/scripts/native/build_whisper_ios.sh"
else
  echo "==> Skipping whisper.cpp (--skip-whisper)"
fi

if [[ "$include_catalyst" == 1 ]]; then
  "${repository_root}/scripts/native/build_catalyst_slice.sh" llama
  if [[ "$skip_whisper" == 0 ]]; then
    "${repository_root}/scripts/native/build_catalyst_slice.sh" whisper
  fi
fi

echo "==> Native frameworks are ready"
