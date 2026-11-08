#!/bin/zsh
# Writes a 6 s vertical and a 5 s horizontal test clip (with a tone), and a vertical clip with
# someone talking (for captions), into $1 (default: ./.samples).
OUT=${1:-${0:A:h}/.samples}; mkdir -p $OUT
ffmpeg -loglevel error -y -f lavfi -i "testsrc2=size=1080x1920:rate=30:duration=6" -f lavfi -i "sine=frequency=440:duration=6" -c:v h264_videotoolbox -b:v 6M -c:a aac -shortest $OUT/vertical-sample.mp4
ffmpeg -loglevel error -y -f lavfi -i "smptebars=size=1920x1080:rate=30:duration=5" -f lavfi -i "sine=frequency=660:duration=5" -c:v h264_videotoolbox -b:v 6M -c:a aac -shortest $OUT/horizontal-sample.mp4
say -v Samantha -o $OUT/speech.aiff "Hey everyone, welcome back to the channel. Today I am showing you the fastest way to edit a short. First, cut the boring parts. Then add captions, because most people watch without sound."
ffmpeg -loglevel error -y -f lavfi -i "testsrc2=size=1080x1920:rate=30" -i $OUT/speech.aiff -c:v h264_videotoolbox -b:v 6M -c:a aac -shortest $OUT/talking-sample.mp4
rm $OUT/speech.aiff
echo $OUT
