#!/usr/bin/env python3
"""Report a looped audio file's seam metrics, for verifying WAV->OGG conversion.

Decodes ANY ffmpeg-readable file (wav/ogg/...) to mono signed-16 PCM and prints
one space-separated line:

    <samples> <first> <last> <wrap> <peak>

- samples : total mono sample count (the loop length the engine replays)
- first   : value of sample 0
- last    : value of the final sample
- wrap    : |last - first| -- the discontinuity the loop wrap crosses
- peak    : max |sample| (amplitude reference for judging `wrap`)

Used by tools/convert_music.sh: the encoded OGG must keep the SAME sample count
as its WAV master (a change means a loop gap), and `wrap` should stay close (the
seamless crossfade tolerates small lossy drift). See the Soundtrack section of
CLAUDE.md for the loop recipe these masters were carved with.
"""
import subprocess
import struct
import sys


def decode_mono_s16(path):
    """Return the file as a list of mono int16 samples via ffmpeg."""
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path,
         "-ac", "1", "-ar", "44100", "-f", "s16le", "-"],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    ).stdout
    return struct.unpack("<%dh" % (len(raw) // 2), raw)


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: check_loop_seam.py <audio-file>")
    smp = decode_mono_s16(sys.argv[1])
    if not smp:
        sys.exit("no samples decoded from %s" % sys.argv[1])
    first, last = smp[0], smp[-1]
    peak = max(abs(min(smp)), abs(max(smp)))
    print("%d %d %d %d %d" % (len(smp), first, last, abs(last - first), peak))


if __name__ == "__main__":
    main()
