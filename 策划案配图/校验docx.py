# -*- coding: utf-8 -*-
"""校验生成的 docx：包结构、XML 合法性、排版要求落实情况。"""
import zipfile
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
P = ROOT / "《檐下千秋》游戏策划案（正式稿）.docx"

z = zipfile.ZipFile(P)
print("包路径:", P.name)
print("坏文件:", z.testzip() or "无")

names = z.namelist()
print("部件数:", len(names))
print("图片数:", len([n for n in names if n.startswith("word/media/")]))

bad = []
for n in names:
    if n.endswith((".xml", ".rels")):
        try:
            ET.fromstring(z.read(n))
        except Exception as e:
            bad.append((n, str(e)))
print("XML 解析:", "全部通过" if not bad else f"有 {len(bad)} 个错误 {bad}")

d = z.read("word/document.xml").decode("utf-8")
f = z.read("word/footnotes.xml").decode("utf-8")

checks = [
    ("关键词蓝色高亮 run", d.count('w:val="0000FF"'), ">0"),
    ("正文蓝色高亮字符出现位置", d.count("<w:color"), ">0"),
    ("脚注引用数", d.count("<w:footnoteReference"), ">0"),
    ("footnotes.xml 中脚注条数", f.count("<w:footnote w:id=") - 2, ">0"),
    ("嵌入图片 drawing 数（3 张设计图）", d.count("<w:drawing>"), "=3"),
    ("页边距 2.54cm (1440 twips)", 1 if 'w:top="1440"' in d and 'w:left="1440"' in d else 0, "=1"),
    ("标题黑体三号 (32 半磅)", d.count('w:val="32"'), ">0"),
    ("正文行距 1.5 倍 (line=360)", d.count('w:line="360"'), ">0"),
    ("封面页存在", 1 if "《檐下千秋》游戏策划案" in d else 0, "=1"),
    ("表格数量", d.count("<w:tbl>"), ">0"),
]
for name, val, expect in checks:
    print(f"  {name:32} {val:>6}   期望 {expect}")

# 页数估算：按段落与图片估算
print()
print("文件大小: %.1f MB" % (P.stat().st_size / 1024 / 1024))
