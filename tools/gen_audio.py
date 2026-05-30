#!/usr/bin/env python3
"""Procedural audio generator for usagi-geo-td.

Synthesizes the SFX set (sfx/*.wav) and a low ambient loop (music/theme.wav)
from pure-Python oscillators — no external deps, no binary assets to commit by
hand. Re-run after tweaking to regenerate:

    python3 tools/gen_audio.py

Usagi maps a file stem to a sound name: sfx/kill.wav -> sfx.play("kill").
"""

import math
import os
import random
import struct
import wave

SR = 44100
random.seed(1)


# ----------------------------------------------------------------- oscillators
def square(f, t):
    return 1.0 if (t * f) % 1.0 < 0.5 else -1.0


def saw(f, t):
    return 2.0 * ((t * f) % 1.0) - 1.0


def sine(f, t):
    return math.sin(2.0 * math.pi * f * t)


def env(t, dur, a=0.005, r=0.04):
    """Linear attack/release envelope."""
    if t < a:
        return t / a
    if t > dur - r:
        return max(0.0, (dur - t) / r)
    return 1.0


def render(dur, fn, amp=0.3):
    n = int(SR * dur)
    return [max(-1.0, min(1.0, fn(i / SR) * amp)) for i in range(n)]


def write_wav(path, samples):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = b"".join(struct.pack("<h", int(s * 32767)) for s in samples)
        w.writeframes(frames)
    print(f"  wrote {path} ({len(samples) / SR:.2f}s)")


# ----------------------------------------------------------------------- sfx
def sfx_shoot():
    dur = 0.08
    return render(dur, lambda t: square(900 - 5200 * t, t) * env(t, dur), 0.28)


def sfx_hit():
    dur = 0.05
    return render(dur, lambda t: (square(1500, t) * 0.5 + random.uniform(-1, 1) * 0.5) * env(t, dur), 0.24)


def sfx_kill():
    dur = 0.14
    return render(dur, lambda t: square(620 - 3000 * t + math.sin(t * 80) * 30, t) * env(t, dur), 0.30)


def sfx_place():
    dur = 0.09
    return render(dur, lambda t: (square(220, t) * 0.6 + sine(90, t) * 0.4) * env(t, dur), 0.30)


def sfx_sell():
    dur = 0.14

    def fn(t):
        f = 520 if t < 0.07 else 320
        return square(f, t)

    return render(dur, lambda t: fn(t) * env(t, dur), 0.26)


def sfx_wave():
    dur = 0.24
    notes = [294, 392, 523]

    def fn(t):
        i = min(2, int(t / 0.08))
        local = t - i * 0.08
        return square(notes[i], t) * env(local, 0.08, 0.004, 0.02)

    return render(dur, fn, 0.26)


def sfx_boss():
    dur = 0.7
    return render(dur, lambda t: (saw(92 + math.sin(t * 8) * 6, t) * 0.6
                                  + random.uniform(-1, 1) * 0.2) * env(t, dur, 0.02, 0.2), 0.32)


def sfx_boss_die():
    dur = 0.7
    return render(dur, lambda t: (saw(300 - 360 * t, t) * 0.5
                                  + random.uniform(-1, 1) * (1.0 - t / dur) * 0.6) * env(t, dur, 0.005, 0.3), 0.34)


def sfx_life():
    dur = 0.26

    def fn(t):
        f = 660 if (t * 12) % 2 < 1 else 440
        return square(f, t)

    return render(dur, lambda t: fn(t) * env(t, dur, 0.005, 0.05), 0.26)


def sfx_upgrade():
    dur = 0.34
    notes = [523, 659, 784, 1047]

    def fn(t):
        i = min(3, int(t / 0.085))
        local = t - i * 0.085
        return (sine(notes[i], t) * 0.6 + square(notes[i], t) * 0.2) * env(local, 0.085, 0.004, 0.04)

    return render(dur, fn, 0.26)


def sfx_click():
    dur = 0.03
    return render(dur, lambda t: square(1200, t) * env(t, dur, 0.002, 0.01), 0.20)


def sfx_over():
    dur = 0.6
    notes = [440, 330, 247, 165]

    def fn(t):
        i = min(3, int(t / 0.15))
        local = t - i * 0.15
        return square(notes[i], t) * env(local, 0.15, 0.005, 0.05)

    return render(dur, fn, 0.28)


# ---------------------------------------------------------------------- music
def music_theme():
    """~12.8s seamless minor-key arpeggio loop with a soft drone, low volume."""
    bpm = 96
    step = 60.0 / bpm / 2.0          # eighth notes
    steps = 32
    dur = step * steps
    # A natural minor arpeggio pattern (Hz)
    arp = [220.0, 261.63, 329.63, 440.0, 329.63, 261.63]
    pattern = [arp[i % len(arp)] for i in range(steps)]
    drone = 110.0

    def fn(t):
        i = int(t / step) % steps
        local = t - i * step
        note = pattern[i]
        voice = (sine(note, t) * 0.5 + sine(note * 2.005, t) * 0.18) * env(local, step, 0.01, step * 0.5)
        bass = sine(drone, t) * 0.22 + sine(drone * 1.5, t) * 0.06
        pad = sine(drone * 2, t) * 0.05 * (0.5 + 0.5 * math.sin(t * 0.6))
        return voice + bass + pad

    return render(dur, fn, 0.5)


SFX = {
    "shoot": sfx_shoot, "hit": sfx_hit, "kill": sfx_kill, "place": sfx_place,
    "sell": sfx_sell, "wave": sfx_wave, "boss": sfx_boss, "boss_die": sfx_boss_die,
    "life": sfx_life, "upgrade": sfx_upgrade, "click": sfx_click, "over": sfx_over,
}

if __name__ == "__main__":
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    print("sfx:")
    for name, gen in SFX.items():
        write_wav(os.path.join(root, "sfx", f"{name}.wav"), gen())
    print("music:")
    write_wav(os.path.join(root, "music", "theme.wav"), music_theme())
    print("done.")
