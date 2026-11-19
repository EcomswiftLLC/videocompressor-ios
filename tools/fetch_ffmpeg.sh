#!/bin/bash
# Downloads the LGPL FFmpeg xcframework and headers from the public build repo and checks their SHA-256.
# Usage: tools/fetch_ffmpeg.sh [tag]   (CI runs it before `xcodegen generate`)
set -euo pipefail
cd "$(dirname "$0")/.."
TAG="${1:-$(cat tools/ffmpeg-release.txt)}"
REPO="EcomswiftLLC/ffmpeg-ios-lgpl"
BASE="https://github.com/$REPO/releases/download/$TAG"
rm -rf Vendor && mkdir -p Vendor && cd Vendor

curl -fsSL --retry 4 -o checksums.txt "$BASE/checksums.txt"
for f in FFmpegLGPL.xcframework.zip FFmpegLGPL-headers.zip; do
  curl -fsSL --retry 4 -o "$f" "$BASE/$f"
  expected=$(grep " $f\$" checksums.txt | awk '{print $1}')
  actual=$(shasum -a 256 "$f" | awk '{print $1}')
  if [ -z "$expected" ] || [ "$expected" != "$actual" ]; then
    echo "Checksum mismatch for $f (expected '$expected', got '$actual')" >&2
    exit 1
  fi
  unzip -q "$f"
  rm "$f"
done
echo "FFmpeg $TAG ready in Vendor/"
ls Vendor 2>/dev/null || ls
