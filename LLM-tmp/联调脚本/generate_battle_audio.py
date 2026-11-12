"""Original, reproducible percussion-led battle loop and boss impact."""
from pathlib import Path
import wave

import numpy as np

RATE = 22050
DEST = Path(__file__).resolve().parents[1] / "客户端/assets/audio"
RNG = np.random.default_rng(20261112)


def mix_at(bus, seconds, sound, gain=1.0):
    start = int(seconds * RATE)
    end = min(len(bus), start + len(sound))
    if end > start:
        bus[start:end] += sound[:end - start] * gain


def tone(frequency, seconds, decay, harmonics=(1.0, .3, .12)):
    t = np.arange(int(seconds * RATE)) / RATE
    wavelet = sum(amp * np.sin(2 * np.pi * frequency * (i + 1) * t)
                  for i, amp in enumerate(harmonics))
    return wavelet * np.exp(-decay * t) * np.minimum(1, t * 260)


def drum(seconds=.35, base=72):
    t = np.arange(int(seconds * RATE)) / RATE
    phase = 2 * np.pi * (base * t + 65 * (1 - np.exp(-t * 38)) / 38)
    return np.sin(phase) * np.exp(-t * 19) + RNG.standard_normal(len(t)) * np.exp(-t * 90) * .20


def crack(seconds=.18):
    t = np.arange(int(seconds * RATE)) / RATE
    noise = RNG.standard_normal(len(t))
    # Difference noise gives a sharp, papery transient without a sample library.
    return (noise - np.roll(noise, 1)) * np.exp(-t * 35) * .19


def save(name, samples):
    if name != "battle.wav":
        attack = min(int(.005 * RATE), len(samples))
        samples[:attack] *= np.linspace(0, 1, attack)
        ramp = min(int(.05 * RATE), len(samples))
        samples[-ramp:] *= np.linspace(1, 0, ramp)
    peak = float(np.max(np.abs(samples)))
    if peak > 0.95:
        samples = samples * (.95 / peak)
    pcm = np.asarray(np.clip(samples, -1, 1) * 32767, dtype="<i2")
    with wave.open(str(DEST / name), "wb") as output:
        output.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
        output.writeframes(pcm.tobytes())
    print(name, "duration", round(len(samples) / RATE, 2), "peak", round(float(np.max(np.abs(pcm))) / 32767, 3))


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    bpm = 120
    beat = 60 / bpm
    duration = 16.0
    score = np.zeros(int(duration * RATE), dtype=np.float64)
    pentatonic = [196.00, 233.08, 261.63, 293.66, 349.23, 392.00, 466.16, 523.25]
    motif = [4, 5, 7, 5, 4, 2, 3, 4, 5, 7, 6, 5, 4, 3, 2, 3,
             4, 5, 7, 6, 5, 4, 3, 2, 3, 4, 5, 7, 6, 5, 4, 3]
    for step in range(32):
        at = step * beat
        mix_at(score, at, drum(), .31 if step % 4 == 0 else .22)
        if step % 2 == 1:
            mix_at(score, at, crack(), .21)
        if step % 4 == 2:
            mix_at(score, at, drum(.27, 105), .15)
        if step % 8 in (3, 7):
            mix_at(score, at + beat * .5, crack(.13), .13)
        mix_at(score, at, tone(pentatonic[motif[step]], .52, 7, (1, .36, .15)), .17)
        bass = pentatonic[[0, 0, 2, 2, 3, 3, 1, 1][(step // 4) % 8]] / 2
        mix_at(score, at, tone(bass, .48, 5, (1, .25, .05)), .28)
        if step % 8 in (0, 4):
            mix_at(score, at, tone(pentatonic[motif[step]] / 2, 1.4, 2.1,
                                   (1, .18, .4, .12)), .11)
    # Match start/end to silence over 25 ms so Godot's forward loop does not click.
    ramp = int(.025 * RATE)
    score[:ramp] *= np.linspace(0, 1, ramp)
    score[-ramp:] *= np.linspace(1, 0, ramp)
    save("battle.wav", score)

    arrival = np.zeros(int(1.7 * RATE), dtype=np.float64)
    for at, pitch, power in [(0, 67, .42), (.12, 78, .33), (.42, 59, .46), (.75, 92, .27)]:
        mix_at(arrival, at, drum(.62, pitch), power)
    mix_at(arrival, .02, crack(.48), .25)
    mix_at(arrival, .32, tone(98, 1.2, 2.8, (1, .48, .2)), .38)
    mix_at(arrival, .77, tone(196, .8, 4.2, (1, .45, .2)), .23)
    save("boss_arrival.wav", arrival)

    strike = np.zeros(int(.35 * RATE), dtype=np.float64)
    mix_at(strike, 0, crack(.25), .33)
    mix_at(strike, .01, drum(.29, 135), .29)
    save("battle_strike.wav", strike)


if __name__ == "__main__":
    main()
