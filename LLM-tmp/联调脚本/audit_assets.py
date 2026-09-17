"""Check shipped audio signal and narrative resource references; no save mutations."""
from pathlib import Path
import argparse
import array
import json
import math
import wave

root = Path(__file__).resolve().parents[1]
client = root / "客户端"
catalog = json.loads((root / "服务端/content/chapters.json").read_text(encoding="utf-8"))
index = json.loads((client / "assets/voice/index.json").read_text(encoding="utf-8"))
issues = []
expected = []
for chapter in catalog["chapters"]:
    for event in chapter["events"]:
        story = event["story"]
        for group, suffix in [("dialogue", "dialogue"), ("clues", "clue"), ("beats", "beat")]:
            for i, line in enumerate(story.get(group, []), 1):
                expected.append(f'{event["id"]}_{suffix}_{i:02}')
        for field, suffix in [("keep_response", "keep"), ("forget_response", "forget"), ("outro", "outro"), ("before_battle", "before_battle"), ("chapter_outro", "chapter_outro"), ("first_clear_whisper", "first_clear")]:
            if story.get(field):
                expected.append(f'{event["id"]}_{suffix}')
for cue in expected:
    if cue not in index["cues"]:
        issues.append(f"Missing narrative cue: {cue}")

resources = []
def inspect(value):
    if isinstance(value, dict):
        for item in value.values(): inspect(item)
    elif isinstance(value, list):
        for item in value: inspect(item)
    elif isinstance(value, str):
        if "\ufffd" in value: issues.append(f"Replacement character: {value}")
        if value.startswith("res://"):
            resources.append(value)
            if not (client / value[6:]).is_file(): issues.append(f"Missing resource: {value}")
inspect(catalog)
inspect(index)

audio = []
for path in sorted((client / "assets").rglob("*.wav")):
    with wave.open(str(path), "rb") as stream:
        if stream.getsampwidth() != 2 or stream.getcomptype() != "NONE":
            issues.append(f"Unexpected PCM format: {path.name}")
            continue
        samples = array.array("h", stream.readframes(stream.getnframes()))
        seconds = stream.getnframes() / stream.getframerate()
        peak = max(map(abs, samples), default=0)
        rms = math.sqrt(sum(float(v)*v for v in samples) / max(1, len(samples)))
        clipped = sum(abs(v) >= 32767 for v in samples)
        if not peak or seconds <= 0: issues.append(f"Empty/silent audio: {path.name}")
        if clipped / max(1, len(samples)) > .001: issues.append(f"Clipped PCM: {path.name}")
        audio.append({"file": str(path.relative_to(client)), "seconds": round(seconds, 3), "peak": peak, "rms": round(rms, 2), "clipped_samples": clipped})
result = {"audio_files": len(audio), "voice_cues": len(index["cues"]), "narrative_cues_checked": len(expected), "resource_references": len(resources), "issues": issues, "audio": audio}
parser = argparse.ArgumentParser()
parser.add_argument("--output", type=Path)
args = parser.parse_args()
if args.output:
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
print(json.dumps({key: value for key, value in result.items() if key != "audio"}, ensure_ascii=False))
raise SystemExit(bool(issues))
