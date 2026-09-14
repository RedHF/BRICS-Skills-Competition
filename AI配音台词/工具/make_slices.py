# -*- coding: utf-8 -*-
"""
方案一：把台词切成便于逐个生成配音的文本文件。

背景（实测自 C:\\Users\\21178\\Desktop\\files\\chatTTS\\ChatTTS\\norm.py）：

ChatTTS 的 normalizer 只保留 [\\u4e00-\\u9fff A-Za-z ，。、,. 空格]，
其余字符会先经一张很小的映射表，之后仍不合法的字符会被 **静默删除**。
映射表只覆盖：：；！（ ）【】『』「」《》－ : ; ! ( ) > < -
因此 '？' '——' '……' '‘' '’' '□' 以及阿拉伯数字都会被直接删掉。

本脚本按语义把这些字符换成 ChatTTS 支持、且能保留停顿的标点，
避免“先帮我记住两个字——平安”被读成“先帮我记住两个字平安”。
"""
import csv
import json
import re
from pathlib import Path

ROOT = Path(r"C:\Users\21178\Desktop\files\BRICS-Skills-Competition")
SRC = ROOT / "AI配音台词" / "台词清单.jsonl"
OUT = ROOT / "AI配音台词" / "切片"

# 顺序敏感：长串必须先替换
PUNCT_MAP = [
    ("——", "，"),
    ("—", "，"),
    ("……", "，"),
    ("…", "，"),
    ("？", "。"),
    ("！", "。"),
    ("：", "，"),
    ("；", "，"),
    ("‘", ""),
    ("’", ""),
    ("“", ""),
    ("”", ""),
    ("「", ""),
    ("」", ""),
    ("□", "，"),
]

# ChatTTS 最终允许的字符
ALLOWED = re.compile(r"[\u4e00-\u9fffA-Za-z，。、,. ]")
REAL_CHAR = re.compile(r"[\u4e00-\u9fffA-Za-z]")
DIGITS = re.compile(r"[0-9]")


def normalize(text: str):
    """返回 (规范化文本, 被替换的字符集合)"""
    changed = set()
    out = text
    for a, b in PUNCT_MAP:
        if a in out:
            changed.update(a)
            out = out.replace(a, b)
    out = re.sub(r"，{2,}", "，", out)
    out = re.sub(r"。{2,}", "。", out)
    out = re.sub(r"\s{2,}", " ", out)
    return out.strip(), changed


def main():
    rows = [json.loads(l) for l in SRC.read_text(encoding="utf-8-sig").splitlines() if l.strip()]

    if OUT.exists():
        for p in OUT.rglob("*"):
            if p.is_file():
                p.unlink()
    OUT.mkdir(parents=True, exist_ok=True)

    # 角色按句数排序
    order = {}
    for r in rows:
        role = r["speaker"] or "旁白"
        order[role] = order.get(role, 0) + 1
    roles = sorted(order.keys(), key=lambda k: (-order[k], k))
    role_idx = {r: i + 1 for i, r in enumerate(roles)}

    manifest = []
    skipped = []
    n_changed = 0
    n_digits = 0

    for i, r in enumerate(rows, 1):
        role = r["speaker"] or "旁白"
        raw = r["text"]
        norm, changed = normalize(raw)

        if changed:
            n_changed += 1
        if DIGITS.search(norm):
            n_digits += 1

        if not norm.strip() or not REAL_CHAR.search(norm):
            skipped.append((r["id"], role, raw, "规范化后无实际汉字/字母（纯标点），无法合成"))
            continue

        folder = OUT / f"{role_idx[role]:02d}-{role}"
        folder.mkdir(parents=True, exist_ok=True)
        txt = folder / f"{i:03d}-{r['id']}.txt"
        txt.write_text(norm, encoding="utf-8")

        manifest.append({
            "序号": i,
            "行ID": r["id"],
            "角色": role,
            "类别": r["category_cn"],
            "章节": r["chapter"],
            "原文": raw,
            "规范化文本": norm,
            "已改写": "是" if changed else "",
            "被替换字符": "".join(sorted(changed)),
            "输出音频": r["suggest_audio"],
            "切片文件": str(txt.relative_to(OUT)).replace("\\", "/"),
            "字数": len(norm),
        })

    with (OUT / "manifest.csv").open("w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(manifest[0].keys()))
        w.writeheader()
        w.writerows(manifest)

    # 规范化对照表（人工审阅用）
    lines = []
    lines.append("规范化对照表")
    lines.append(f"共 {len(manifest)} 条可合成，{len(skipped)} 条跳过。其中 {n_changed} 条被改写过标点。")
    lines.append("")
    lines.append("规则：—— / …… -> ，（保留停顿）     ？ -> 。     ‘ ’ “ ” -> 删除     □ -> ，")
    lines.append("原因：ChatTTS 的 normalizer 会静默删除这些字符，导致停顿丢失、疑问语气消失。")
    lines.append("")
    lines.append("=" * 110)
    for m in manifest:
        if not m["已改写"]:
            continue
        lines.append(f"[{m['行ID']}]  {m['角色']}   替换字符: {m['被替换字符']}")
        lines.append(f"  原文  : {m['原文']}")
        lines.append(f"  实际读: {m['规范化文本']}")
        lines.append("")
    if skipped:
        lines.append("=" * 110)
        lines.append("以下行规范化后为空，无法合成：")
        lines.append("")
        for sid, role, raw, why in skipped:
            lines.append(f"  [{sid}] {role}  原文={raw!r}  原因={why}")
    (OUT / "00-规范化对照.txt").write_text("\n".join(lines), encoding="utf-8-sig")

    print(f"输出目录: {OUT}")
    print(f"可合成  : {len(manifest)} 条")
    print(f"跳过    : {len(skipped)} 条")
    print(f"改写标点: {n_changed} 条")
    print(f"含数字  : {n_digits} 条")
    print("")
    print("按角色：")
    for r in roles:
        c = sum(1 for m in manifest if m["角色"] == r)
        print(f"  {role_idx[r]:02d}-{r:<14} {c:>3} 条")


if __name__ == "__main__":
    main()
