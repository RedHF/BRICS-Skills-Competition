"""Original, reproducible fast battle score and boss impacts."""
import argparse
from pathlib import Path
import wave

import numpy as np

RATE = 22050
DEST = Path(__file__).resolve().parents[1] / "客户端/assets/audio"
RNG = np.random.default_rng(20261112)
BATTLE_BPM = 160
BATTLE_BARS = 16


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


def snare(seconds=.23):
    t = np.arange(int(seconds * RATE)) / RATE
    noise = RNG.standard_normal(len(t))
    noise = noise - np.roll(noise, 2)
    body = np.sin(2 * np.pi * (190 * t - 46 * t * t)) * np.exp(-t * 23)
    return noise * np.exp(-t * 21) * .13 + body * .29


def hat(seconds=.07):
    t = np.arange(int(seconds * RATE)) / RATE
    noise = RNG.standard_normal(len(t))
    return (noise - np.roll(noise, 1)) * np.exp(-t * 65) * .09


def bowed_string(frequency, seconds):
    """Nasal bowed-string color with a sliding attack and delayed vibrato."""
    t = np.arange(int(seconds * RATE)) / RATE
    vibrato = .008 * np.sin(2 * np.pi * 5.7 * t) * (1 - np.exp(-8 * np.maximum(0, t - .09)))
    slide = -.065 * np.exp(-t * 21)
    phase = 2 * np.pi * np.cumsum(frequency * (1 + vibrato + slide)) / RATE
    harmonics = (.50, .85, .62, .34, .18, .09)
    voice = sum(amp * np.sin(phase * (index + 1) + index * .12)
                for index, amp in enumerate(harmonics))
    attack = np.minimum(1, t / .075)
    release = np.minimum(1, np.maximum(0, seconds - t) / .13)
    bow = .93 + .07 * np.sin(2 * np.pi * 7.4 * t)
    texture = RNG.standard_normal(len(t)) * .012
    return (voice + texture) * attack * release * bow


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


def main(battle_only=False):
    DEST.mkdir(parents=True, exist_ok=True)
    beat = 60 / BATTLE_BPM
    duration = BATTLE_BARS * 4 * beat
    score = np.zeros(int(duration * RATE), dtype=np.float64)
    pentatonic = [392.00, 466.16, 523.25, 587.33, 698.46, 783.99]
    bass_roots = [98.00, 87.31, 116.54, 98.00]
    for step in range(BATTLE_BARS * 4):
        at = step * beat
        beat_in_bar = step % 4
        bar = step // 4
        if beat_in_bar in (0, 2):
            mix_at(score, at, drum(.3, 76), .43 if beat_in_bar == 0 else .35)
        if beat_in_bar in (1, 3):
            mix_at(score, at, snare(), .37)
            mix_at(score, at, drum(.22, 103), .13)
        if beat_in_bar == 3:
            mix_at(score, at + beat * .5, drum(.19, 93), .22)
        if bar % 4 == 3 and beat_in_bar == 3:
            for subdivision in range(1, 4):
                mix_at(score, at + subdivision * beat * .25,
                       snare(.14), .12 + subdivision * .045)
        for subdivision in range(4):
            mix_at(score, at + subdivision * beat * .25, hat(),
                   .24 if subdivision in (0, 2) else .15)
        root = bass_roots[(bar // 2) % len(bass_roots)]
        mix_at(score, at, tone(root, .32, 8, (1, .38, .12)), .23)
        if beat_in_bar in (0, 2):
            mix_at(score, at + beat * .5, tone(root * 2, .19, 14, (1, .45, .12)), .075)

    # Four evolving phrases keep the lead moving without breaking the loop's meter.
    phrase = [(0, 1.5, 0), (1.5, .5, 1), (2, 1, 2), (3, .5, 3), (3.5, .5, 2),
              (4, 1, 1), (5, .5, 0), (5.5, .5, 1), (6, 1, 3), (7, 1, 2),
              (8, .5, 3), (8.5, .5, 4), (9, 1, 5), (10, .5, 4), (10.5, .5, 3),
              (11, 1, 2), (12, .5, 1), (12.5, .5, 2), (13, .5, 3),
              (13.5, .5, 4), (14, 1, 3), (15, 1, 0)]
    for repeat in range(4):
        for start, length, pitch in phrase:
            note = min(5, pitch + (1 if repeat == 2 and start < 8 else 0))
            mix_at(score, (repeat * 16 + start) * beat,
                   bowed_string(pentatonic[note], length * beat * .98), .115)
    for bar in range(BATTLE_BARS):
        if bar % 2 == 0:
            mix_at(score, bar * 4 * beat, bowed_string(bass_roots[(bar // 2) % 4] * 2,
                   1.7 * beat), .034)

    # Match start/end to silence so Godot's forward loop has no discontinuity.
    ramp = int(.04 * RATE)
    score[:ramp] *= np.linspace(0, 1, ramp)
    score[-ramp:] *= np.linspace(1, 0, ramp)
    save("battle.wav", score)
    print("battle tempo", BATTLE_BPM, "BPM")
    if battle_only:
        return

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
    parser = argparse.ArgumentParser()
    parser.add_argument("--battle-only", action="store_true")
    main(parser.parse_args().battle_only)
