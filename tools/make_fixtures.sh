#!/bin/bash
# Makes small test clips in formats AVFoundation cannot open, using Homebrew's ffmpeg (CI only, never shipped).
# Usage: tools/make_fixtures.sh <output dir>
set -euo pipefail
OUT="${1:?output dir}"
mkdir -p "$OUT"
SRC=(-f lavfi -i "testsrc2=size=640x360:rate=30" -f lavfi -i "sine=frequency=440:sample_rate=44100" -t 3 -shortest)

mk() { # name, then ffmpeg output options
  local name="$1"; shift
  if ffmpeg -y -loglevel error "${SRC[@]}" "$@" "$OUT/$name"; then echo "made $name"; else echo "SKIPPED $name (encoder missing in this ffmpeg)"; rm -f "$OUT/$name"; fi
}

mk sample.mkv  -c:v libx264 -pix_fmt yuv420p -c:a aac
mk sample.avi  -c:v mpeg4 -c:a libmp3lame
mk sample.webm -c:v libvpx-vp9 -b:v 600k -c:a libopus
mk sample.wmv  -c:v wmv2 -c:a wmav2
mk sample.flv  -c:v flv -c:a libmp3lame
mk sample.ts   -c:v libx264 -pix_fmt yuv420p -c:a aac
mk sample.mpg  -c:v mpeg2video -c:a mp2
mk sample.ogv  -c:v libtheora -c:a libvorbis
ls -la "$OUT"
