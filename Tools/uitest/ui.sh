#!/bin/zsh
# Drives the running app for on-screen checks. Needs Screen Recording + Accessibility for the terminal.
#   ui.sh click X Y [count]      real mouse click, X/Y in points relative to the window's top-left
#   ui.sh rclick X Y             right-click (context menu)
#   ui.sh drag X1 Y1 X2 Y2
#   ui.sh move X Y                pointer to X Y without clicking (hover, skimming)
#   ui.sh hold X1 Y1 X2 Y2 / ui.sh release X Y   drag and keep the button down (to screenshot a drag), then let go
#   ui.sh rawkey KEYCODE          a key press posted directly (works while a pop-up menu is open)
#   ui.sh keydrag KEYCODE X1 Y1 X2 Y2   drag while holding a key (15 = R, for a range)
#   ui.sh scroll X Y LINES        scroll wheel (negative LINES shows what is further down)
#   ui.sh key CHAR ["command down"]
#   ui.sh code KEYCODE ["command down"]   (49 space, 51 delete, 115 home, 123/124 arrows)
#   ui.sh shot NAME              window screenshot to $OUT/NAME.png (Retina: 2 px per point)
DIR=${0:A:h}
BIN=$DIR/.bin
OUT=${OUT:-$DIR/.shots}
mkdir -p $BIN $OUT
for t in mouse wid; do
  [[ $BIN/$t -nt $DIR/$t.swift ]] || swiftc -o $BIN/$t $DIR/$t.swift
done
POS=$(osascript -e 'tell application "System Events" to tell process "Shorts Editor" to get position of window 1')
WX=${POS%%,*}; WY=${${POS##*,}// /}
osascript -e 'tell application "Shorts Editor" to activate'; sleep 0.4
case $1 in
  click) $BIN/mouse click $(($WX+$2)) $(($WY+$3)) $4 ;;
  rclick) $BIN/mouse rclick $(($WX+$2)) $(($WY+$3)) ;;
  drag) $BIN/mouse drag $(($WX+$2)) $(($WY+$3)) $(($WX+$4)) $(($WY+$5)) ;;
  hold) $BIN/mouse hold $(($WX+$2)) $(($WY+$3)) $(($WX+$4)) $(($WY+$5)) ;;
  release) $BIN/mouse release $(($WX+$2)) $(($WY+$3)) ;;
  rawkey) $BIN/mouse key $2 ;;
  move) $BIN/mouse move $(($WX+$2)) $(($WY+$3)) ;;
  keydrag) $BIN/mouse keydrag $2 $(($WX+$3)) $(($WY+$4)) $(($WX+$5)) $(($WY+$6)) ;;
  scroll) $BIN/mouse scroll $(($WX+$2)) $(($WY+$3)) $4 ;;
  key) M=""; [[ -n $3 ]] && M=" using {$3}"; osascript -e "tell application \"System Events\" to keystroke \"$2\"$M" ;;
  code) M=""; [[ -n $3 ]] && M=" using {$3}"; osascript -e "tell application \"System Events\" to key code $2$M" ;;
  shot) screencapture -x -o -l "$($BIN/wid)" "$OUT/$2.png" && echo "$OUT/$2.png" ;;
esac
