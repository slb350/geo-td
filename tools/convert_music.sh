#!/usr/bin/env bash
# Transcode the seam-carved music masters (music_src/*.wav) to loop-safe OGG
# Vorbis in music/ -- the runtime tracks the engine actually loads. Usagi
# recommends OGG for music (small + cross-platform); the WAV masters stay in
# music_src/, which is NOT a runtime dir, so they never ship in an export.
#
# The masters are already seamless 34s-ish loops (see CLAUDE.md "Soundtrack");
# this is a straight transcode, NOT a re-carve. The verification gate is the
# delicate bit: a Vorbis decode that changed the sample count would put a gap at
# the loop wrap, so each OGG is decoded back and checked to match its WAV master
# sample-for-sample in length. Wrap-delta drift is reported for the human seam
# check (the crossfade tolerates small lossy perturbation; a length change does
# not). A track that fails the length gate fails the whole script (exit 1) so the
# release gate blocks -- we never ship a clicking loop.
#
# Re-runnable: overwrites music/*.ogg in place. Encodes with oggenc (the
# reference libvorbis encoder, from vorbis-tools); the seam check decodes the
# result with ffmpeg. Requires oggenc + ffmpeg + python3.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/music_src"
OUT="$ROOT/music"
SEAM="$ROOT/tools/check_loop_seam.py"

# The runtime stems lib/audio.lua rotates (POOL). theme is legacy/unused at
# runtime, so it is NOT converted -- its master just lives in music_src/.
# Pass stem name(s) as args to convert only those (e.g. after re-looping one
# track); with no args, all runtime stems are (re)encoded.
STEMS=(menu combat combat2 combat3 combat4 combat5 boss boss2 boss3)
[[ "$#" -gt 0 ]] && STEMS=("$@")

QUALITY="${OGG_QUALITY:-7}"   # oggenc -q (0..10, override via env); 7 ~ transparent for short loops

fail=0
printf '%-10s %10s %10s %8s %8s  %s\n' track wav_smp ogg_smp wav_wrap ogg_wrap result
for stem in "${STEMS[@]}"; do
  wav="$SRC/$stem.wav"
  ogg="$OUT/$stem.ogg"
  if [[ ! -f "$wav" ]]; then
    printf '%-10s %46s  %s\n' "$stem" "" "MISSING MASTER"; fail=1; continue
  fi

  oggenc -Q -q "$QUALITY" -o "$ogg" "$wav"

  read -r w_smp _ _ w_wrap _ < <(python3 "$SEAM" "$wav")
  read -r o_smp _ _ o_wrap _ < <(python3 "$SEAM" "$ogg")

  if [[ "$w_smp" == "$o_smp" ]]; then
    result="ok (len match)"
  else
    # Length changed -> the loop wrap would gap. Don't ship it: fail the gate and
    # leave the bad .ogg in place for inspection (handle that track by hand).
    result="LEN MISMATCH (gap risk)"; fail=1
  fi
  printf '%-10s %10s %10s %8s %8s  %s\n' "$stem" "$w_smp" "$o_smp" "$w_wrap" "$o_wrap" "$result"
done

echo
echo "music/ now:"; (cd "$OUT" && ls -1 && echo "size: $(du -sh . | cut -f1)")
if [[ "$fail" -ne 0 ]]; then
  echo "WARN: at least one track did not convert cleanly (see above)." >&2
  exit 1
fi
echo "All runtime tracks converted to OGG; sample counts preserved."
echo "Human step: 'usagi run .' and confirm each loop wraps without a click."
