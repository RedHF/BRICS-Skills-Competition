"""Regenerate packaged speech with Qwen Audio 3.1; credentials only in the environment.

Set DASHSCOPE_API_KEY, then run with --limit 3 for a sample or no limit for all.
Outputs are staged; --install requires a complete, validated set of 184 files.
"""
import argparse
import concurrent.futures
import csv
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import threading
import time
import urllib.error
import urllib.request
import wave

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
MODEL = "qwen-audio-3.1-tts-flash"
HOST = "https://ws-rm2bko34pj2cxlth.cn-beijing.maas.aliyuncs.com"
OUT = ROOT / ".review/qwen-tts"
REPORT = ROOT / "Art_Material/Generation/生成音频/Qwen-3.1/generation-report.json"
ROLE_VOICES = {
    "拓印师": "longanzhi_v3.1",
    "檐下谱": "xieshurou_v3.1", "旁白": "xieshurou_v3.1",
    "廊桥": "longsanshu_v3.1", "廊桥的回声": "longsanshu_v3.1",
    "社庙": "xuyanchu_v3.1", "社庙·客声": "anmingyuan_v3.1",
    "社庙·童声": "longniuniu_v3.1",
    "戏楼": "xiaoxingzhi_v3.1", "戏楼的回声": "xiaoxingzhi_v3.1",
    "戏楼·师父回声": "longsanshu_v3.1", "戏楼·旦角回声": "longanya_v3.1",
    "牌坊": "huozhuoshi_v3.1", "牌坊·匠人回声": "xunanchuan_v3.1",
    "墨塔": "xunanchuan_v3.1", "飞鸟山": "longzhe_v3.1",
    "初代回声": "longsanshu_v3.1", "初代拓印师·塔中回声": "longsanshu_v3.1",
    "墨灵回声": "xieshurou_v3.1",
}
INSTRUCTION = "用自然连贯的普通话朗读，语速适中，吐字清晰，情感克制。不加笑声、气声或背景音。"
LOCK = threading.Lock()
LAST_REQUEST = 0.0


def get_rows():
    with (ROOT / "AI配音台词/切片/manifest.csv").open(encoding="utf-8-sig") as f:
        return list(csv.DictReader(f))


def clean_audio(raw):
    with wave.open(io.BytesIO(raw), "rb") as wav:
        rate, width, channels = wav.getframerate(), wav.getsampwidth(), wav.getnchannels()
        if width != 2 or rate != 24000 or channels != 1:
            raise ValueError(f"Unexpected PCM format: {rate}/{width}/{channels}")
        pcm = np.frombuffer(wav.readframes(wav.getnframes()), dtype="<i2").astype(np.float64) / 32768
    if pcm.size < rate * .3 or not np.isfinite(pcm).all():
        raise ValueError("Invalid or too short audio")
    # Remove DC offset and only trim near-silent edges, retaining a 100 ms lead/tail.
    pcm -= pcm.mean()
    active = np.flatnonzero(np.abs(pcm) > .003)
    if active.size < rate * .1:
        raise ValueError("Silent audio")
    pcm = pcm[max(0, active[0] - rate // 10):min(pcm.size, active[-1] + rate // 10 + 1)]
    voiced = pcm[np.abs(pcm) > .01]
    rms = float(np.sqrt(np.mean(voiced ** 2)))
    peak = float(np.abs(pcm).max())
    gain = min(10 ** (-20 / 20) / max(rms, 1e-6), 10 ** (-3 / 20) / peak)
    pcm *= gain
    fade = min(int(rate * .008), len(pcm) // 2)
    pcm[:fade] *= np.linspace(0, 1, fade)
    pcm[-fade:] *= np.linspace(1, 0, fade)
    result = io.BytesIO()
    with wave.open(result, "wb") as wav:
        wav.setparams((1, 2, rate, 0, "NONE", "not compressed"))
        wav.writeframes(np.rint(pcm * 32767).astype("<i2").tobytes())
    return result.getvalue(), {"seconds": round(len(pcm) / rate, 3),
                              "peak_dbfs": round(20 * np.log10(np.abs(pcm).max()), 2),
                              "gain_db": round(20 * np.log10(gain), 2),
                              "sample_rate": rate, "channels": 1}


def synthesize(row, key):
    global LAST_REQUEST
    name, role, text = row["输出音频"], row["角色"], row["原文"]
    voice = ROLE_VOICES[role]
    fingerprint = hashlib.sha256((MODEL + voice + text + INSTRUCTION).encode()).hexdigest()
    dest = OUT / role / name
    meta = dest.with_suffix(".json")
    if dest.exists() and meta.exists():
        record = json.loads(meta.read_text(encoding="utf-8"))
        if record.get("fingerprint") == fingerprint and record.get("sha256") == hashlib.sha256(dest.read_bytes()).hexdigest():
            return record
    payload = {"model": MODEL, "input": {"text": text, "voice": voice, "format": "wav",
                                          "sample_rate": 24000, "instruction": INSTRUCTION}}
    for attempt in range(4):
        try:
            with LOCK:
                time.sleep(max(0, .45 - (time.monotonic() - LAST_REQUEST)))
                LAST_REQUEST = time.monotonic()
            req = urllib.request.Request(HOST + "/api/v1/services/audio/tts/SpeechSynthesizer",
                data=json.dumps(payload).encode(), headers={"Authorization": "Bearer " + key,
                                                           "Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=90) as response:
                data = json.load(response)
            url = data["output"]["audio"]["url"].replace("http://", "https://", 1)
            # Never send the API credential to the result storage host.
            with urllib.request.urlopen(url, timeout=60) as response:
                audio, quality = clean_audio(response.read())
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(audio)
            record = {"id": row["行ID"], "file": str(dest.relative_to(OUT)), "role": role,
                      "voice": voice, "model": MODEL, "text": text, "instruction": INSTRUCTION,
                      "request_id": data.get("request_id"), "usage": data.get("usage"),
                      "fingerprint": fingerprint, "sha256": hashlib.sha256(audio).hexdigest(), **quality}
            meta.write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding="utf-8")
            print("OK", name, quality["seconds"], flush=True)
            return record
        except urllib.error.HTTPError as e:
            # Do not log authorization headers, signed URLs, or response bodies.
            if e.code not in (429, 500, 502, 503, 504):
                raise RuntimeError(f"{name}: HTTP {e.code}") from None
        except (TimeoutError, urllib.error.URLError):
            pass
        time.sleep(2 ** attempt)
    raise RuntimeError(f"{name}: failed after four attempts")


def install(rows, records):
    target = ROOT / "LLM-tmp/客户端/assets/voice"
    expected = {Path(p).name for p in json.loads((target / "index.json").read_text(encoding="utf-8"))["cues"].values()}
    if {Path(r["file"]).name for r in records} != expected or len(records) != 184:
        raise ValueError("Refusing partial installation")
    backup = ROOT / ".review/tts/previous-voice"
    backup.mkdir(parents=True, exist_ok=True)
    for record in records:
        source = OUT / record["file"]
        dest = target / source.name
        if not (backup / dest.name).exists():
            shutil.copy2(dest, backup / dest.name)
        shutil.copy2(source, dest)
    print("INSTALLED", len(records), flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--install", action="store_true")
    args = parser.parse_args()
    rows = get_rows()
    if args.limit:
        rows = rows[:args.limit]
    key = os.environ["DASHSCOPE_API_KEY"]
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        records = list(pool.map(lambda row: synthesize(row, key), rows))
    OUT.mkdir(parents=True, exist_ok=True)
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(records, ensure_ascii=False, indent=2), encoding="utf-8")
    if args.install:
        install(rows, records)
    print("COMPLETE", len(records), "files", round(sum(r["seconds"] for r in records), 1), "seconds", flush=True)


if __name__ == "__main__":
    main()
