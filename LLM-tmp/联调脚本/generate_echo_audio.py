"""Reproducible, synthetic physical-object cues for the echo temple chapter.

No recordings, voice generation, or outside samples are used. The private
child response reuses an existing, separately gated voice asset in the client.
"""

from pathlib import Path
import math
import random
import struct
import wave

RATE = 24000
OUT = Path(__file__).resolve().parents[1] / "客户端" / "assets" / "echo_v1"


def write(name, duration, modes, noise_level):
    rng = random.Random(731)
    samples = []
    noise = 0.0
    for i in range(int(duration * RATE)):
        t = i / RATE
        noise = .62 * noise + .38 * rng.uniform(-1, 1)
        value = sum(amplitude * math.sin(2 * math.pi * frequency * t)
                    * math.exp(-decay * t)
                    for frequency, amplitude, decay in modes)
        value += noise * noise_level * math.exp(-40 * t)
        value *= min(1, t / .004) * min(1, (duration-t)/.08)
        samples.append(value)
    peak = max(abs(value) for value in samples)
    pcm = b"".join(struct.pack("<h", round(value / peak * 23000)) for value in samples)
    with wave.open(str(OUT / name), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(pcm)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    write("drum_single.wav", 1.4,
          [(76, 1, 4.4), (121, .55, 5.8), (163, .26, 8.1),
           (221, .14, 10), (303, .075, 14)], .23)
    write("distant_gong.wav", 2.6,
          [(208, .5, 1.8), (303, .23, 2.1), (433, .19, 2.4),
           (591, .11, 2.8), (817, .08, 3.2)], .06)
    print("Created two synthetic mono PCM cues at 24000 Hz.")
