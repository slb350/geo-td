#!/usr/bin/env python3
"""Re-cut a seamless music master to a WHOLE-NUMBER-OF-BARS loop length.

Why: the originals were carved to a fixed ~34s window (see CLAUDE.md "Soundtrack").
If 34s is not an integer number of bars for the track's tempo, the loop point lands
a fraction of a bar off the beat grid, so a beat is heard "repeating" at the start
and at each wrap. This trims the loop to the nearest whole-bar length and re-seals
the seam with a tail-first crossfade (same seam order as the carve recipe), which
removes the fractional-bar drift without needing the original long render.

The source master is ALREADY a seamless loop, so the tail crossfade samples are read
with wraparound (S is circular: S[L0-1] -> S[0] is smooth), and the new wrap
S[L1-1] -> S[L1] is adjacent in the source => seamless by construction.

Tempo is estimated from an onset-energy autocorrelation (pure Python, no numpy);
pass --bpm to override if you know it (you made the track). Nothing in music_src/
or music/ is modified -- outputs are written to an audition dir for you to judge:
  <stem>_reloop.wav        the new whole-bar loop (1x) -- the candidate master
  <stem>_reloop_x3.wav     the candidate looped 3x -- listen at the wrap points
  <stem>_current_x3.wav    the CURRENT loop 3x -- A/B reference

Usage:  python3 tools/reloop_music.py <stem> [--bpm N] [--bars K] [--xfade SEC]
"""
import argparse
import os
import struct
import subprocess
import wave

HOP = 512  # envelope frame size in samples


def read_wav_mono_s16(path):
    w = wave.open(path, "rb")
    if w.getsampwidth() != 2 or w.getnchannels() != 1:
        raise SystemExit("expected mono 16-bit PCM: %s" % path)
    sr = w.getframerate()
    n = w.getnframes()
    smp = list(struct.unpack("<%dh" % n, w.readframes(n)))
    w.close()
    return smp, sr


def write_wav_mono_s16(path, smp, sr):
    w = wave.open(path, "wb")
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(sr)
    w.writeframes(struct.pack("<%dh" % len(smp), *smp))
    w.close()


def estimate_beat_samples(smp, sr):
    """Return (beat_samples, bpm) from an onset-energy autocorrelation."""
    nfr = len(smp) // HOP
    energy = [0.0] * nfr
    for i in range(nfr):
        base = i * HOP
        acc = 0.0
        for j in range(base, base + HOP):
            v = smp[j] / 32768.0
            acc += v * v
        energy[i] = acc
    # half-wave-rectified energy difference = a cheap onset envelope
    onset = [0.0] * nfr
    for i in range(1, nfr):
        d = energy[i] - energy[i - 1]
        onset[i] = d if d > 0 else 0.0
    mean = sum(onset) / nfr
    o = [v - mean for v in onset]
    fps = sr / HOP                       # envelope frames per second
    lag_min = int(round(fps * 60 / 180))  # 180 BPM
    lag_max = int(round(fps * 60 / 70))   # 70 BPM
    best_lag, best_val = lag_min, -1e18
    for lag in range(lag_min, lag_max + 1):
        acc = 0.0
        for i in range(lag, nfr):
            acc += o[i] * o[i - lag]
        if acc > best_val:
            best_val, best_lag = acc, lag
    beat_samples = best_lag * HOP
    return beat_samples, 60.0 / (beat_samples / sr)


def crossfade_reloop(smp, L1, xfade):
    """Tail-first crossfade into a seamless loop of length L1 (source is circular)."""
    L0 = len(smp)
    out = smp[:L1]                       # body = S[0:L1]
    for i in range(xfade):
        fo = 1.0 - i / xfade             # tail fades out (linear / ffmpeg 'tri')
        fi = i / xfade                   # body fades in
        tail = smp[(L1 + i) % L0]        # tail = S[L1 + i], wrapped (S loops)
        v = int(round(tail * fo + out[i] * fi))
        out[i] = max(-32768, min(32767, v))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("stem")
    ap.add_argument("--bpm", type=float, default=None)
    ap.add_argument("--bars", type=int, default=None)
    ap.add_argument("--xfade", type=float, default=0.4)
    ap.add_argument("--beats-per-bar", type=int, default=4)
    args = ap.parse_args()

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    src = os.path.join(root, "music_src", args.stem + ".wav")
    outdir = os.path.join(root, "export", "audio_audition")
    os.makedirs(outdir, exist_ok=True)

    smp, sr = read_wav_mono_s16(src)
    L0 = len(smp)

    if args.bpm:
        beat_samples, bpm = int(round(sr * 60 / args.bpm)), args.bpm
        src_note = "given"
    else:
        beat_samples, bpm = estimate_beat_samples(smp, sr)
        src_note = "estimated"
    bar = beat_samples * args.beats_per_bar

    K = args.bars or round(L0 / bar)
    while K * bar > L0:                  # body must fit; tail wraps for the rest
        K -= 1
    L1 = K * bar
    xfade = min(int(args.xfade * sr), L1 // 4)

    print("source     : %s (%d samples, %.3fs @ %d)" % (src, L0, L0 / sr, sr))
    print("tempo      : %.2f BPM (%s); beat=%d smp, bar=%d smp (%d/4)"
          % (bpm, src_note, beat_samples, bar, args.beats_per_bar))
    print("current    : %.3f bars in the 34s window (off by %.3f bar)"
          % (L0 / bar, abs(L0 / bar - round(L0 / bar))))
    print("re-loop    : %d bars -> %d samples (%.3fs); trims %d smp (%.3fs); xfade %.2fs"
          % (K, L1, L1 / sr, L0 - L1, (L0 - L1) / sr, xfade / sr))

    out = crossfade_reloop(smp, L1, xfade)

    reloop = os.path.join(outdir, args.stem + "_reloop.wav")
    write_wav_mono_s16(reloop, out, sr)
    write_wav_mono_s16(os.path.join(outdir, args.stem + "_reloop_x3.wav"), out * 3, sr)
    write_wav_mono_s16(os.path.join(outdir, args.stem + "_current_x3.wav"), smp * 3, sr)
    print("wrote      : %s/%s_{reloop,reloop_x3,current_x3}.wav" % (outdir, args.stem))
    print("audition   : afplay '%s/%s_current_x3.wav'  vs  afplay '%s/%s_reloop_x3.wav'"
          % (outdir, args.stem, outdir, args.stem))


if __name__ == "__main__":
    main()
