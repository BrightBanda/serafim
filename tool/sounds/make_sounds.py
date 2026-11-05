"""Makes the app's in-app sounds (assets/sounds/*.wav): calm and ambient.

    python3 tool/sounds/make_sounds.py "path/to/Default 2.wav"

Every sound starts softly (no click), stays in a warm register, decays from
the first moment, and fades into a short reverb tail, at a low level. The
Serafim sound is the owner's own recording, softened the same way; the rest
are synthesised here, so they carry no licence.
"""
import sys
import wave
from pathlib import Path

import numpy as np

SR = 22050
OUT = Path(__file__).resolve().parents[2] / "assets" / "sounds"
RNG = np.random.default_rng(7)


def t_of(n):
    return np.arange(n) / SR


def envelope(n, attack, decay):
    """A soft fade-in, then an exponential decay from the start."""
    t = t_of(n)
    rise = np.clip(t / attack, 0, 1) ** 2
    return rise * np.exp(-t / decay)


def lowpass(x, cutoff):
    """One-pole low-pass, twice (gentle 12 dB/octave)."""
    a = np.exp(-2 * np.pi * cutoff / SR)
    for _ in range(2):
        y = np.empty_like(x)
        acc = 0.0
        for i, v in enumerate(x):
            acc = (1 - a) * v + a * acc
            y[i] = acc
        x = y
    return x


def reverb(x, seconds=1.1, wet=0.35, tone=2200):
    """A small, dark room: decaying filtered noise as the impulse response."""
    n = int(SR * seconds)
    ir = RNG.normal(0, 1, n) * np.exp(-t_of(n) / (seconds / 6.9))
    ir = lowpass(ir, tone)
    ir[: int(SR * 0.012)] = 0  # a short gap before the reflections
    ir /= np.sqrt(np.sum(ir**2))
    tail = np.convolve(x, ir)
    dry = np.pad(x, (0, len(tail) - len(x)))
    return (1 - wet) * dry + wet * tail * 3


def tone(freq, dur, attack, decay, partials=((1, 1.0),), glide=0.0):
    n = int(SR * dur)
    t = t_of(n)
    f = freq * (1 + glide * t / dur)
    phase = 2 * np.pi * np.cumsum(f) / SR
    x = sum(a * np.sin(h * phase) for h, a in partials)
    return x * envelope(n, attack, decay)


def mix(*parts):
    """[(start seconds, signal)] summed."""
    n = max(int(s * SR) + len(x) for s, x in parts)
    out = np.zeros(n)
    for s, x in parts:
        i = int(s * SR)
        out[i : i + len(x)] += x
    return out


def save(name, x, peak):
    x = x / np.max(np.abs(x)) * peak
    fade = int(SR * 0.05)
    x[-fade:] *= np.linspace(1, 0, fade)
    # Trim the silent end of the tail.
    keep = np.where(np.abs(x) > peak * 0.004)[0]
    x = x[: keep[-1] + 1 if len(keep) else len(x)]
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype("<i2").tobytes())
    print(f"{name}: {len(x) / SR:.2f} s, peak {peak}")


def serafim(source):
    """The owner's sound, kept recognisable but calmed down."""
    with wave.open(source) as w:
        rate = w.getframerate()
        raw = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(float)
        if w.getnchannels() == 2:
            raw = raw.reshape(-1, 2).mean(axis=1)
    raw /= 32768
    # Resample to SR.
    idx = np.arange(0, len(raw), rate / SR)
    x = np.interp(idx, np.arange(len(raw)), raw)
    x = lowpass(x, 1600)
    x *= envelope(len(x), attack=0.04, decay=0.22)
    return reverb(x, seconds=1.2, wet=0.4, tone=1800)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    if len(sys.argv) > 1:
        save("serafim", serafim(sys.argv[1]), peak=0.32)

    soft = ((1, 1.0), (2, 0.08))

    # A water drop, low and round.
    save("drop", reverb(tone(620, 0.35, 0.008, 0.09, soft, glide=-0.35), wet=0.4), peak=0.3)

    # Two soft notes, a fifth apart, overlapping.
    save(
        "chime",
        reverb(
            mix(
                (0.0, tone(523.25, 1.0, 0.015, 0.35, soft)),
                (0.14, tone(783.99, 1.1, 0.02, 0.4, soft)),
            ),
            wet=0.4,
        ),
        peak=0.28,
    )

    # A single glassy note, gently struck.
    save(
        "ping",
        reverb(tone(880, 1.2, 0.012, 0.45, ((1, 1.0), (2.01, 0.12), (3.0, 0.03))), wet=0.42),
        peak=0.26,
    )

    # Two small rising bubbles.
    save(
        "bubble",
        reverb(
            mix(
                (0.0, tone(330, 0.18, 0.006, 0.05, soft, glide=0.35)),
                (0.09, tone(440, 0.2, 0.006, 0.06, soft, glide=0.3)),
            ),
            wet=0.35,
        ),
        peak=0.28,
    )

    # A breath of air for a sent message.
    n = int(SR * 0.42)
    air = lowpass(RNG.normal(0, 1, n), 900)
    air *= np.sin(np.pi * t_of(n) / (n / SR)) ** 2
    save("swoosh", reverb(air, seconds=0.6, wet=0.25), peak=0.2)

    # A soft wooden tap for typing.
    tap = tone(700, 0.12, 0.003, 0.025, ((1, 1.0), (2.4, 0.15)))
    save("tick", reverb(tap, seconds=0.4, wet=0.25), peak=0.14)


if __name__ == "__main__":
    main()
