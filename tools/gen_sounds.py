#!/usr/bin/env python3
"""Generates the farm's soft sound effects into sounds/ (16-bit mono WAV).

    python3 -I tools/gen_sounds.py            (from anywhere inside the repo)

Standard library only (wave, struct, math, random). The output is
deterministic (fixed random seed), so re-running gives identical files.
Every effect is short, quiet (peak well under full scale) and has soft
attack/release envelopes so nothing clicks. Replace any file with real audio
at the same path; the game needs no code change.
"""
import math
import os
import random
import struct
import wave

RATE = 22050
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
OUT = os.path.join(ROOT, 'sounds')


def env(i, n, attack=0.01, release=0.6):
    """Linear attack, exponential-ish release, as a 0..1 gain for sample i of n."""
    t = i / RATE
    dur = n / RATE
    a = min(1.0, t / attack) if attack > 0 else 1.0
    k = t / dur
    r = (1 - k) ** (1.0 / max(0.05, release)) if k < 1 else 0.0
    return a * r


def tone(freq_fn, dur, peak, wave_fn=math.sin, attack=0.005, release=0.5, noise=0.0, rng=None):
    n = int(RATE * dur)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        phase += 2 * math.pi * freq_fn(t) / RATE
        s = wave_fn(phase)
        if noise and rng:
            s = s * (1 - noise) + (rng.random() * 2 - 1) * noise
        out.append(s * peak * env(i, n, attack, release))
    return out


def noise_burst(dur, peak, lowpass=0.2, attack=0.002, release=0.4, rng=None):
    """Filtered noise (one-pole low-pass, `lowpass` in 0..1; smaller = duller)."""
    n = int(RATE * dur)
    out, y = [], 0.0
    for i in range(n):
        x = rng.random() * 2 - 1
        y += lowpass * (x - y)
        out.append(y * peak * env(i, n, attack, release))
    return out


def mix(*tracks, offsets=None):
    offsets = offsets or [0] * len(tracks)
    n = max(int(o * RATE) + len(t) for t, o in zip(tracks, offsets))
    out = [0.0] * n
    for t, o in zip(tracks, offsets):
        start = int(o * RATE)
        for i, s in enumerate(t):
            out[start + i] += s
    return out


def tri(p):
    return 2 / math.pi * math.asin(math.sin(p))


def write(name, samples):
    path = os.path.join(OUT, name)
    peak = max(1e-9, max(abs(s) for s in samples))
    if peak > 0.95:                      # never clip
        samples = [s * 0.95 / peak for s in samples]
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, s)) * 32767)) for s in samples))
    print('%-12s %5.2f s  peak %.2f  -> %s' % (name, len(samples) / RATE, max(abs(s) for s in samples),
                                               os.path.relpath(path, ROOT)))


def main():
    os.makedirs(OUT, exist_ok=True)
    rng = random.Random(20261107)

    # till: a dull earthy thud (low sine drop + muffled noise)
    write('till.wav', mix(
        tone(lambda t: 140 - 260 * t, 0.16, 0.45, release=0.35),
        noise_burst(0.12, 0.35, lowpass=0.08, release=0.3, rng=rng)))

    # plant: a soft rising pop
    write('plant.wav', tone(lambda t: 380 + 900 * t, 0.12, 0.35, wave_fn=tri, release=0.4))

    # water: a few bubbly droplets over a gentle splash
    drops = [tone(lambda t, f=f: f + 1400 * t, 0.07, 0.18, release=0.35) for f in (900, 1150, 780, 1300)]
    write('water.wav', mix(noise_burst(0.28, 0.16, lowpass=0.25, attack=0.02, release=0.5, rng=rng),
                           *drops, offsets=[0, 0.02, 0.08, 0.13, 0.19]))

    # harvest: a bright two-note pluck
    write('harvest.wav', mix(tone(lambda t: 660, 0.14, 0.28, wave_fn=tri, release=0.35),
                             tone(lambda t: 990, 0.18, 0.24, wave_fn=tri, release=0.35), offsets=[0, 0.06]))

    # sell: a cheerful little chime (three rising notes)
    write('sell.wav', mix(*[tone(lambda t, f=f: f, 0.16, 0.2, release=0.35) for f in (784, 988, 1175)],
                          offsets=[0, 0.06, 0.12]))

    # buy: a soft descending two-note chime
    write('buy.wav', mix(tone(lambda t: 1047, 0.12, 0.2, release=0.35),
                         tone(lambda t: 784, 0.16, 0.2, release=0.35), offsets=[0, 0.07]))

    # coin: a tiny, quiet tick for the coin counter
    write('coin.wav', tone(lambda t: 2093, 0.045, 0.12, release=0.3))

    # deny: a quiet, low "bonk" (soft, not harsh)
    write('deny.wav', tone(lambda t: 220 - 60 * t, 0.14, 0.2, wave_fn=tri, release=0.4))

    # glitch: a bit-crushed warble with noise (the break)
    def crushed(p):
        return round(math.sin(p) * 3) / 3
    write('glitch.wav', mix(
        tone(lambda t: 180 + 140 * math.sin(t * 55), 0.7, 0.3, wave_fn=crushed, release=0.7, noise=0.25, rng=rng),
        noise_burst(0.5, 0.15, lowpass=0.6, release=0.6, rng=rng), offsets=[0, 0.05]))


if __name__ == '__main__':
    main()
