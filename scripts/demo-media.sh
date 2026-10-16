#!/bin/sh
# Writes the demo video of the demo pack (task 0018, step 20):
# content/demo/media/assistant-demo.webm, eight seconds of the testsrc2 and
# sine sources at 640x360, encoded with the VP9 and Opus settings of the
# media converter (Espalier.Media.Ffmpeg.video_args/3). Run it through the
# shell of the repository: nix-shell --run scripts/demo-media.sh
set -eu

out="content/demo/media/assistant-demo.webm"

ffmpeg -nostdin -hide_banner -loglevel error -y \
  -f lavfi -i "testsrc2=size=640x360:rate=30:duration=8" \
  -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=8" \
  -map 0:v:0 -map 1:a:0 -map_metadata -1 -map_chapters -1 \
  -c:v libvpx-vp9 -b:v 0 -crf 32 -deadline good -cpu-used 4 -row-mt 1 -g 240 \
  -pix_fmt yuv420p -c:a libopus -b:a 96k -ac 2 -threads 2 -fflags +bitexact \
  -f webm "$out"

echo "wrote $out"
