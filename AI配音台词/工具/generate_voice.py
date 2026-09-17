# -*- coding: utf-8 -*-
"""
方案二：用本地 ChatTTS 批量生成配音。

用法（必须在 chatTTS 的 venv 里跑）：

  set PYTHONUTF8=1
  set NO_PROXY=localhost,127.0.0.1,::1
  C:\\Users\\21178\\Desktop\\files\\chatTTS\\.venv\\Scripts\\python.exe generate_voice.py --limit 5
  ...\\generate_voice.py --role 拓印师
  ...\\generate_voice.py                      # 全量 184 条
  ...\\generate_voice.py --audition 8         # 试听 8 个候选声线

每个角色固定一个声线（seed 决定），声线向量缓存在 speakers.json，
改里面的 seed 就能换某个角色的声音，不用重跑全部。

输出：生成音频\\<角色>\\<建议音频名>.wav
      22050 Hz / 单声道 / 16-bit PCM，与游戏现有 assets/echo 格式一致。
"""
import argparse
import csv
import json
import os
import re
import sys
import time
from pathlib import Path

CHATTTS_DIR = Path(r"C:\Users\21178\Desktop\files\chatTTS")
MODEL_DIR = CHATTTS_DIR / "models" / "2Noise" / "ChatTTS"
ROOT = Path(r"C:\Users\21178\Desktop\files\BRICS-Skills-Competition")
SLICE_DIR = ROOT / "AI配音台词" / "切片"
OUT_DIR = ROOT / "AI配音台词" / "生成音频"
TOOL_DIR = ROOT / "AI配音台词" / "工具"
SPK_FILE = TOOL_DIR / "speakers.json"

sys.path.insert(0, str(CHATTTS_DIR))
os.chdir(CHATTTS_DIR)

import numpy as np                      # noqa: E402
import scipy.io.wavfile as wavfile      # noqa: E402
import scipy.signal as signal           # noqa: E402
import torch                            # noqa: E402

SRC_SR = 24000     # ChatTTS 输出采样率
DST_SR = 22050     # 游戏现有音频采样率

AUDITION_LINES = [
    "名字可以慢慢找。先帮我记住两个字，平安。",
    "我的名字也被雨洗掉了吗。",
    "雨停了。你醒在桥心，手中只有一本空白册子。",
]


def safe(name: str) -> str:
    return re.sub(r'[\\/:*?"<>|]', "_", name)


def seed_for(role: str, index: int) -> int:
    return 20260914 + index * 7919


def load_speakers(chat, roles):
    """每个角色一个固定声线，缓存到 speakers.json。"""
    data = {}
    if SPK_FILE.exists():
        data = json.loads(SPK_FILE.read_text(encoding="utf-8"))
    changed = False
    for i, role in enumerate(roles):
        if role not in data or "spk_emb" not in data[role]:
            seed = seed_for(role, i)
            torch.manual_seed(seed)
            emb = chat.sample_random_speaker()
            data[role] = {"seed": seed, "spk_emb": emb}
            changed = True
            print(f"  新声线 {role} (seed={seed})")
    if changed:
        SPK_FILE.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
    return data


def to_wav(audio, path: Path):
    arr = np.asarray(audio, dtype=np.float32).reshape(-1)
    if DST_SR != SRC_SR:
        arr = signal.resample_poly(arr, DST_SR, SRC_SR).astype(np.float32)
    peak = float(np.max(np.abs(arr))) if arr.size else 0.0
    if peak > 0.99:
        arr = arr / peak * 0.99
    pcm = (np.clip(arr, -1.0, 1.0) * 32767.0).astype(np.int16)
    path.parent.mkdir(parents=True, exist_ok=True)
    wavfile.write(str(path), DST_SR, pcm)
    return arr.size / DST_SR


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0, help="只跑前 N 条（试跑用）")
    ap.add_argument("--role", default="", help="只跑某个角色")
    ap.add_argument("--audition", type=int, default=0, help="生成 N 个候选声线试听")
    ap.add_argument("--batch", type=int, default=6, help="每批合成条数")
    ap.add_argument("--no-refine", action="store_true", help="跳过 refine 阶段")
    ap.add_argument("--force", action="store_true", help="重生成已存在的文件")
    args = ap.parse_args()

    man_path = SLICE_DIR / "manifest.csv"
    if not man_path.exists():
        sys.exit(f"找不到 {man_path}，请先运行 make_slices.py")
    with man_path.open(encoding="utf-8-sig") as f:
        rows = list(csv.DictReader(f))

    print(f"torch {torch.__version__} | cuda={torch.cuda.is_available()}")
    import ChatTTS
    chat = ChatTTS.Chat()
    t0 = time.time()
    if not chat.load(source="custom", custom_path=str(MODEL_DIR), compile=False):
        sys.exit("模型加载失败")
    print(f"模型加载完成 {time.time() - t0:.1f}s\n")

    # ---------- 试听模式 ----------
    if args.audition:
        out = ROOT / "AI配音台词" / "试听"
        out.mkdir(parents=True, exist_ok=True)
        print(f"生成 {args.audition} 个候选声线，试听目录: {out}\n")
        line = AUDITION_LINES[1]
        for k in range(args.audition):
            seed = 20260914 + k * 7919
            torch.manual_seed(seed)
            spk = chat.sample_random_speaker()
            p = ChatTTS.Chat.InferCodeParams(spk_emb=spk, temperature=0.3, top_P=0.7, top_K=20)
            t1 = time.time()
            wavs = chat.infer([line], skip_refine_text=args.no_refine,
                              split_text=False, params_infer_code=p)
            dur = to_wav(wavs[0], out / f"候选{k + 1:02d}-seed{seed}.wav")
            print(f"  候选{k + 1:02d} seed={seed}  {dur:.2f}s  ({time.time() - t1:.1f}s)")
        print(f"\n挑好之后，把 speakers.json 里对应角色的 seed 改成喜欢的那个即可。")
        return

    # ---------- 筛选 ----------
    todo = rows
    if args.role:
        todo = [r for r in todo if r["角色"] == args.role]
        if not todo:
            sys.exit(f"没有角色 {args.role}")
    if args.limit:
        todo = todo[:args.limit]

    roles = sorted({r["角色"] for r in rows})
    print(f"角色声线：")
    speakers = load_speakers(chat, roles)
    print()

    # ---------- 按角色分组批处理 ----------
    groups = {}
    for r in todo:
        groups.setdefault(r["角色"], []).append(r)

    done = 0
    skipped = 0
    t_start = time.time()
    results = []

    for role, items in groups.items():
        spk = speakers[role]["spk_emb"]
        params = ChatTTS.Chat.InferCodeParams(spk_emb=spk, temperature=0.3, top_P=0.7, top_K=20)
        out_role = OUT_DIR / f"{safe(role)}"
        print(f"── {role}  ({len(items)} 条)")

        pending = []
        for r in items:
            dst = out_role / r["输出音频"]
            if dst.exists() and not args.force:
                skipped += 1
                continue
            pending.append(r)

        for i in range(0, len(pending), args.batch):
            chunk = pending[i:i + args.batch]
            texts = [r["规范化文本"] for r in chunk]
            t1 = time.time()
            try:
                wavs = chat.infer(texts, skip_refine_text=args.no_refine,
                                  split_text=False, params_infer_code=params)
            except Exception as e:
                print(f"    !! 批次失败: {e}")
                continue
            dt = time.time() - t1

            if len(wavs) != len(chunk):
                print(f"    !! 返回 {len(wavs)} 条，期望 {len(chunk)} 条，本批逐条重试")
                for r in chunk:
                    try:
                        w1 = chat.infer([r["规范化文本"]], skip_refine_text=args.no_refine,
                                        split_text=False, params_infer_code=params)
                        wavs_one = w1[0] if w1 else None
                    except Exception as e:
                        print(f"      失败 {r['行ID']}: {e}")
                        continue
                    if wavs_one is None:
                        continue
                    dur = to_wav(wavs_one, out_role / r["输出音频"])
                    done += 1
                    results.append((r, dur))
                continue

            for r, w in zip(chunk, wavs):
                dur = to_wav(w, out_role / r["输出音频"])
                results.append((r, dur))
                done += 1
                print(f"    {r['行ID']:<42} {dur:5.2f}s")
            print(f"    -- 本批 {len(chunk)} 条 / {dt:.1f}s")

    # ---------- 清单 ----------
    if results:
        rep = TOOL_DIR / "生成记录.csv"
        new = not rep.exists()
        with rep.open("a", encoding="utf-8-sig", newline="") as f:
            w = csv.writer(f)
            if new:
                w.writerow(["行ID", "角色", "类别", "文本", "音频", "时长秒"])
            for r, dur in results:
                w.writerow([r["行ID"], r["角色"], r["类别"], r["规范化文本"],
                            f"{safe(r['角色'])}/{r['输出音频']}", f"{dur:.2f}"])

    el = time.time() - t_start
    total_dur = sum(d for _, d in results)
    print(f"\n完成 {done} 条，跳过已存在 {skipped} 条，用时 {el / 60:.1f} 分钟")
    print(f"音频总时长 {total_dur / 60:.1f} 分钟")
    print(f"输出目录: {OUT_DIR}")


if __name__ == "__main__":
    main()
