"""Material-specific procedural Foley; no recordings or external samples."""
from array import array
import hashlib
import json
import math
from pathlib import Path
import random
import wave

RATE = 32000
OUT = Path(__file__).resolve().parents[1] / "客户端/assets/echo_v1/foley"


def render(name, seconds, seed):
    rng = random.Random(seed)
    values = array("f")
    low = slow = 0.0
    wood = name.startswith(("step_wood", "timber", "ward"))
    stone = name.startswith("step_stone")
    for i in range(round(seconds * RATE)):
        t = i / RATE
        white = rng.uniform(-1, 1)
        low += .15 * (white - low)
        slow += .009 * (white - slow)
        grain = low - slow
        value = 0.0
        if wood or stone or name == "pottery_place":
            hits = [(0.012, 1.0)]
            if name == "timber_seat": hits = [(.02, .45), (.17, 1.0), (.205, .2)]
            if name == "timber_support": hits = [(.03, .38), (.31, .8)]
            for at, strength in hits:
                x = t - at
                if x < 0: continue
                modes = [(172, .23, 26), (317, .11, 42), (596, .06, 58)]
                if stone: modes = [(106, .17, 35), (453, .04, 55)]
                if name == "pottery_place": modes = [(634, .12, 7), (1039, .055, 12), (1687, .018, 17)]
                if name == "ward_knock": modes = [(94, .32, 16), (231, .16, 25), (409, .06, 38)]
                value += strength * sum(a*math.sin(2*math.pi*f*x)*math.exp(-d*x) for f,a,d in modes)
                value += strength * grain * (.65 if stone else .35)*math.exp(-x*75)
            if name.startswith("step_"):
                value += grain*(.3 if stone else .13)*math.exp(-((t-.11)/.048)**2)
            if name.startswith("timber"):
                friction = math.sin(math.pi*min(1,t/.32))**2 if t < .32 else 0
                value += grain*.24*friction*(.5+.5*math.sin(t*173)**2)
        elif name.startswith("paper_rub"):
            envelope = math.sin(math.pi*t/seconds)**1.8
            value = ((white-low)*.07 + grain*.34)*envelope
            value *= .55+.45*math.sin(2*math.pi*18*t+.8*math.sin(t*39))**2
        elif name == "paper_fold":
            value = (white-low)*.07*math.exp(-((t-.13)/.085)**2)
            value += grain*.23*math.exp(-((t-.23)/.12)**2)
        elif name == "brush_sweep":
            value = (white-low)*.08*math.sin(math.pi*t/seconds)**2
            value += slow*.7*math.sin(math.pi*t/seconds)**3
        elif name == "erosion_gather":
            rise = min(1,t/.55)*max(0,1-t/seconds)
            value = ((white-low)*.07+grain*.23)*rise
            value *= .2+.8*max(0,math.sin(t*67+math.sin(t*21)))**6
            value += slow*.42*rise
        elif name == "erosion_break":
            value = (white-low)*.14*math.exp(-t*9)
            value += grain*.3*math.exp(-t*5)*(.3+.7*math.sin(t*53)**2)
        elif name == "ink_settle":
            value = grain*.16*math.exp(-t*18)
            value += .12*math.sin(2*math.pi*(147*t-6*t*t))*math.exp(-t*8)
        elif name == "drum_body":
            # Skin membrane's non-harmonic modes and initial pitch fall,
            # followed by two restrained room reflections.
            for delay, reflection in [(0,1),(.137,.13),(.283,.07)]:
                x = t-delay
                if x < 0: continue
                phase = x+.016*(1-math.exp(-14*x))
                modes = [(69, .55, 3.3),(109.7,.25,4.6),(147.7,.16,6.8),
                         (182.8,.09,9.4),(201.5,.07,10.2),(241.5,.035,13)]
                value += reflection*sum(a*math.sin(2*math.pi*f*phase)*math.exp(-d*x) for f,a,d in modes)
                value += reflection*grain*.5*math.exp(-60*x)
        fade = min(1, t/.003, (seconds-t)/.035)
        values.append(value*max(0,fade))
    peak = max(abs(v) for v in values) or 1
    gain = min(10 if name == "erosion_gather" else 1.6, .50/peak)
    pcm = array("h", (round(v*gain*32767) for v in values))
    path = OUT / (name+".wav")
    with wave.open(str(path), "wb") as out:
        out.setparams((1,2,RATE,0,"NONE","not compressed"))
        out.writeframes(pcm.tobytes())
    rms = math.sqrt(sum((v*gain)**2 for v in values)/len(values))
    return {"file":path.name,"duration":seconds,"peak_dbfs":round(20*math.log10(peak*gain),2),
            "rms_dbfs":round(20*math.log10(max(rms,1e-9)),2),
            "sha256":hashlib.sha256(path.read_bytes()).hexdigest()}


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    specs = [("timber_seat", .58), ("timber_support", .8), ("ward_knock", .42),
             ("pottery_place", .8), ("paper_rub_1", .38), ("paper_rub_2", .43),
             ("step_wood_1", .28), ("step_wood_2", .29),
             ("step_stone_1", .25), ("step_stone_2", .27),
             ("paper_fold", .46), ("brush_sweep", .36),
             ("erosion_gather", .85), ("erosion_break", .65), ("ink_settle", .48),
             ("drum_body", 1.9)]
    receipt = {"origin":"procedural synthesis, no recordings or external samples",
               "sample_rate":RATE,"channels":1,"bits":16,"sounds":[render(n,s,904+i*17) for i,(n,s) in enumerate(specs)]}
    (OUT/"制作与电平记录.json").write_text(json.dumps(receipt,ensure_ascii=False,indent=2),encoding="utf-8")
    print(f"Created {len(specs)} material-specific cues; no clipping.")
