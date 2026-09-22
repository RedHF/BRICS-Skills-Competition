# -*- coding: utf-8 -*-
"""验证 md 与 docx 是否已同步：把 md 生成到临时文件，与用户的 docx 逐项比对结构。"""
import html
import importlib.util
import re
import sys
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCX = ROOT / "Task01" / "Original" / "正式成果" / "《檐下千秋》游戏策划案（正式稿）.docx"

spec = importlib.util.spec_from_file_location("gen", ROOT / "策划案配图" / "生成正式稿docx.py")
gen = importlib.util.module_from_spec(spec)
sys.modules["gen"] = gen
spec.loader.exec_module(gen)
tmp = Path(tempfile.mkdtemp())
gen.OUT = tmp / "regen.docx"
gen.main()


def info(p):
    z = zipfile.ZipFile(p)
    d = z.read("word/document.xml").decode("utf-8")
    raw = "".join(re.findall(r"<w:t(?: [^>]*)?>(.*?)</w:t>", d, re.S))
    # 反转义实体后比较（Word 写字面引号，本生成器写 &quot;，渲染结果相同）
    txt = html.unescape(raw)
    return {
        "text": txt,
        "tbl": d.count("<w:tbl>"),
        "img": len([n for n in z.namelist() if n.startswith("word/media/")]),
        "fn": d.count("<w:footnoteReference"),
        "blue": d.count("0000FF"),
        "tblHeader": d.count("<w:tblHeader"),
    }


a = info(DOCX)
b = info(gen.OUT)

print()
print(f"{'项':<16}{'你的 docx':>12}{'md 生成':>12}   一致")
for k in ("tbl", "img", "fn", "blue", "tblHeader"):
    same = "OK" if a[k] == b[k] else "差异"
    print(f"{k:<16}{a[k]:>12}{b[k]:>12}   {same}")
print(f"{'文本长度':<16}{len(a['text']):>12}{len(b['text']):>12}   "
      f"{'OK' if len(a['text']) == len(b['text']) else '差异'}")

print()
segs = ["一、游戏概述", "二、核心玩法", "三、系统设计", "四、可视化表达", "五、AI 赋能",
        "六、文档规范", "七、制作边界"]
print("章节存在性：")
for s in segs:
    print(f"  {s:<14} 你的 docx: {'有' if s in a['text'] else '无':<4}  md: {'有' if s in b['text'] else '无'}")

if a["text"] != b["text"]:
    sm = __import__("difflib").SequenceMatcher(None, a["text"], b["text"])
    print(f"\n文本相似度: {sm.ratio():.5f}")
    n = 0
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == "equal":
            continue
        n += 1
        if n <= 6:
            print(f"  [{tag}] docx={a['text'][max(0,i1-25):i2+25]!r}")
            print(f"        md  ={b['text'][max(0,j1-25):j2+25]!r}")
    print(f"  差异块数: {n}")
else:
    print("\n文本完全一致")
