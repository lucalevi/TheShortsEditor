#!/bin/zsh
# Writes a 6 s vertical and a 5 s horizontal test clip (with a tone), and a vertical clip with
# someone talking (for captions), one with long pauses, a song (music-sample.m4a), a 4 s B-roll clip
# without sound, and two pictures (a horizontal JPEG and a vertical PNG), into $1 (default: ./.samples).
OUT=${1:-${0:A:h}/.samples}; mkdir -p $OUT
ffmpeg -loglevel error -y -f lavfi -i "testsrc2=size=1080x1920:rate=30:duration=6" -f lavfi -i "sine=frequency=440:duration=6" -c:v h264_videotoolbox -b:v 6M -c:a aac -shortest $OUT/vertical-sample.mp4
ffmpeg -loglevel error -y -f lavfi -i "smptebars=size=1920x1080:rate=30:duration=5" -f lavfi -i "sine=frequency=660:duration=5" -c:v h264_videotoolbox -b:v 6M -c:a aac -shortest $OUT/horizontal-sample.mp4
say -v Samantha -o $OUT/speech.aiff "Hey everyone, welcome back to the channel. Today I am showing you the fastest way to edit a short. First, cut the boring parts. Then add captions, because most people watch without sound."
ffmpeg -loglevel error -y -f lavfi -i "testsrc2=size=1080x1920:rate=30" -i $OUT/speech.aiff -c:v h264_videotoolbox -b:v 6M -c:a aac -shortest $OUT/talking-sample.mp4
rm $OUT/speech.aiff
# Long pauses (and a quiet start) for Remove Pauses.
say -v Samantha -o $OUT/pauses.aiff "[[slnc 1200]] Hi there. [[slnc 1500]] So today, [[slnc 1200]] we cut out the pauses. [[slnc 2000]] And that is it."
ffmpeg -loglevel error -y -f lavfi -i "testsrc2=size=1080x1920:rate=30" -i $OUT/pauses.aiff -c:v h264_videotoolbox -b:v 6M -c:a aac -shortest $OUT/pauses-sample.mp4
rm $OUT/pauses.aiff
# A 40 s "song" for Music: a pulsing chord, loud like mastered music.
ffmpeg -loglevel error -y -f lavfi -i "aevalsrc='0.25*(sin(2*PI*220*t)+sin(2*PI*277*t)+sin(2*PI*330*t))*(0.6+0.4*sin(2*PI*2*t))|0.25*(sin(2*PI*220*t)+sin(2*PI*277*t)+sin(2*PI*330*t))*(0.6+0.4*sin(2*PI*2*t+1))':s=48000:d=40" -c:a aac -b:a 192k $OUT/music-sample.m4a
# B-roll and pictures, for showing over clips and as clips.
ffmpeg -loglevel error -y -f lavfi -i "mandelbrot=size=1080x1920:rate=30" -t 4 -c:v h264_videotoolbox -b:v 6M $OUT/broll-sample.mp4
ffmpeg -loglevel error -y -f lavfi -i "testsrc=size=1600x1200:rate=1" -frames:v 1 $OUT/photo-sample.jpg
ffmpeg -loglevel error -y -f lavfi -i "rgbtestsrc=size=1080x1920:rate=1" -frames:v 1 $OUT/portrait-sample.png
# A green screen with a moving patterned square in front, for Stage K (keying, Remove Background).
ffmpeg -loglevel error -y -f lavfi -i "color=c=0x33BF4D:s=1080x1920:r=30:d=5" -f lavfi -i "testsrc2=size=500x700:rate=30:duration=5" -filter_complex "[0][1]overlay=x='200+150*sin(t*2)':y=600,format=yuv420p" -c:v h264_videotoolbox -allow_sw 1 -b:v 6M $OUT/greenscreen-sample.mp4
echo $OUT
