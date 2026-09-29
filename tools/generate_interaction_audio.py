"""Create quiet tactile Foley and a looping pentatonic tracing score.

Uses only the Python standard library and a fixed seed; no external samples.
"""
from __future__ import annotations

from array import array
import math
from pathlib import Path
import random
import wave

RATE = 22050
OUT = Path(__file__).resolve().parents[1] / "LLM-tmp/客户端/assets/audio"
RNG = random.Random(20260929)


def write(name: str, samples: array) -> None:
    peak = max(abs(v) for v in samples) or 1
    gain = min(0.88 / peak, 1.0)
    pcm = array("h", (int(max(-1, min(1, v * gain)) * 32767) for v in samples))
    with wave.open(str(OUT / name), "wb") as target:
        target.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
        target.writeframes(pcm.tobytes())


def foley(duration: float, kind: str) -> array:
    result = array("f")
    low = 0.0
    high = 0.0
    for index in range(int(RATE * duration)):
        t = index / RATE
        white = RNG.uniform(-1, 1)
        low += (white - low) * (0.055 if kind == "page" else 0.12)
        high += (white - high) * 0.008
        grain = low - high
        if kind == "page":
            sweep = math.sin(math.pi * t / duration) ** 1.6
            flap = math.exp(-max(0, t - .34) * 33) if t >= .34 else 0
            value = .32 * grain * sweep + .12 * low * flap
            value += .035 * math.sin(2 * math.pi * 185 * t) * flap
        elif kind == "brush":
            envelope = (1 - math.exp(-t * 130)) * math.exp(-t * 11)
            value = (.34 * grain + .08 * low) * envelope
            value += .025 * math.sin(2 * math.pi * 128 * t) * math.exp(-t * 22)
        else:  # a restrained, soft wooden seal tap rather than a UI beep
            tap = math.exp(-t * 35)
            value = .2 * grain * tap
            value += .12 * math.sin(2 * math.pi * 235 * t) * math.exp(-t * 29)
            value += .06 * math.sin(2 * math.pi * 360 * t) * math.exp(-t * 42)
            value += .035 * math.sin(2 * math.pi * 120 * t) * math.exp(-t * 19)
        result.append(value)
    return result


def tracing_music() -> array:
    seconds = 48
    length = seconds * RATE
    score = array("f", [0.0]) * length
    # Low, slow pentatonic phrases leave room for the story narration.
    notes = [196.0, 220.0, 261.63, 293.66, 329.63, 392.0]
    melody = [0, 2, 3, 2, 1, 0, 3, 4, 5, 3, 2, 1, 0, 2, 4, 3,
              0, 1, 3, 2, 4, 3, 1, 0, 2, 3, 5, 4, 3, 2, 1, 0]
    for beat, note in enumerate(melody):
        start = int(beat * 1.5 * RATE)
        frequency = notes[note]
        for offset in range(int(1.42 * RATE)):
            place = start + offset
            if place >= length:
                break
            t = offset / RATE
            pluck = (1 - math.exp(-t * 95)) * math.exp(-t * 2.1)
            tone = (math.sin(2 * math.pi * frequency * t)
                    + .27 * math.sin(2 * math.pi * frequency * 2 * t) * math.exp(-t * 2.3)
                    + .11 * math.sin(2 * math.pi * frequency * 3 * t) * math.exp(-t * 3.7))
            score[place] += .075 * pluck * tone
    for chord_start in range(0, seconds, 12):
        for frequency in (98.0, 146.83, 196.0):
            begin = chord_start * RATE
            for offset in range(12 * RATE):
                place = begin + offset
                if place >= length:
                    break
                t = offset / RATE
                envelope = min(1, t / 2.0, (12 - t) / 2.0)
                score[place] += .019 * envelope * math.sin(2 * math.pi * frequency * t)
    # Two discreet delay taps make the guqin-like plucks less synthetic.
    for delay, amount in ((int(.19 * RATE), .16), (int(.37 * RATE), .09)):
        for index in range(delay, length):
            score[index] += score[index - delay] * amount
    for index in range(length):
        fade = min(1, index / (.25 * RATE), (length - index) / (.4 * RATE))
        score[index] *= max(0, fade)
    return score


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    write("ui_wood.wav", foley(.25, "wood"))
    write("ui_page.wav", foley(.58, "page"))
    write("brush_touch.wav", foley(.31, "brush"))
    write("trace_music.wav", tracing_music())


if __name__ == "__main__":
    main()
