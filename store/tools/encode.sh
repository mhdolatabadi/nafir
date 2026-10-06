#!/usr/bin/env bash
# Renders the teaser frames and encodes store/listing/rhythmo-teaser-1920x1080.mp4.
# Needs node with Playwright, Chromium and an ffmpeg with libx264 on PATH.
set -euo pipefail
cd "$(dirname "$0")"
rm -rf frames && node teaser.js
# A soft generated pad (Am F C G), so the video carries no licensed music.
i=0
for chord in "220 261.63 329.63" "174.61 220 261.63" "196 261.63 329.63" "196 246.94 293.66"; do
  i=$((i + 1)); set -- $chord
  ffmpeg -hide_banner -loglevel error -y -f lavfi \
    -i "aevalsrc='(0.16*sin(2*PI*$1*t)+0.13*sin(2*PI*$2*t)+0.11*sin(2*PI*$3*t)+0.06*sin(2*PI*$1/2*t))*min(1,t/0.8)*min(1,(3.4-t)/0.9)':s=44100:d=3.4" \
    -ac 2 "frames/c$i.wav"
done
printf "file c%s.wav\n" 1 2 3 4 1 2 3 4 > frames/chords.txt
duration=$(node -e "console.log((3.2 + 5 * 3.4 + 3.6).toFixed(1))")
ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i frames/chords.txt \
  -af "lowpass=f=2200,aecho=0.8:0.7:120|240:0.35|0.25,afade=t=in:d=1.5,afade=t=out:st=$(node -e "console.log($duration - 2)"):d=2,atrim=0:$duration,volume=0.9" \
  frames/pad.wav
ffmpeg -hide_banner -loglevel error -y -framerate 30 -i frames/f%04d.jpg -i frames/pad.wav \
  -c:v libx264 -preset slow -crf 20 -pix_fmt yuv420p -profile:v high -movflags +faststart \
  -c:a aac -b:a 160k -shortest ../listing/rhythmo-teaser-1920x1080.mp4
rm -rf frames
echo "wrote store/listing/rhythmo-teaser-1920x1080.mp4"
