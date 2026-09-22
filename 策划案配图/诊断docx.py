# -*- coding: utf-8 -*-
"""诊断 docx 中残留的 Markdown 记号与字体使用情况。"""
import re
import zipfile
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
z = zipfile.ZipFile(ROOT / "《檐下千秋》游戏策划案（正式稿）.docx")
d = z.read("word/document.xml").decode("utf-8")

# 提取所有 <w:t> 文本（注意排除 <w:tbl> 等标签）
texts = re.findall(r"<w:t(?: [^>]*)?>(.*?)</w:t>", d, re.S)
joined = "".join(texts)

print("=== 1. 残留 Markdown 记号 ===")
for mark, name in [("**", "粗体星号"), ("{{", "关键词标记"), ("}}", "关键词标记"), ("|", "表格竖线"), ("#", "井号")]:
    n = joined.count(mark)
    flag = "" if n == 0 else "  <== 有残留"
    print(f"  {name} {mark!r}: {n}{flag}")

hits = [t for t in texts if "**" in t or "{{" in t or "}}" in t]
if hits:
    print("\n  含残留记号的文本片段（前 20 条）:")
    for t in hits[:20]:
        print("    ·", t[:90])

print()
print("=== 2. 字体使用统计 ===")
fonts = Counter(re.findall(r'w:eastAsia="([^"]+)"', d))
for f, n in fonts.most_common():
    print(f"  {f}: {n}")

print()
print("=== 3. 字号使用统计（半磅） ===")
sizes = Counter(re.findall(r'<w:sz w:val="(\d+)"/>', d))
name_map = {"32": "三号(16pt)", "30": "小三(15pt)", "28": "四号(14pt)",
            "24": "小四(12pt)", "21": "五号(10.5pt)", "22": "小四偏小", "20": "小五偏小",
            "18": "脚注"}
for s, n in sorted(sizes.items(), key=lambda x: -x[1]):
    print(f"  {s} 半磅 = {name_map.get(s, '?'):<12} {n} 处")

print()
print("=== 4. 行距使用统计 ===")
for sp, n in Counter(re.findall(r'w:line="(\d+)"', d)).most_common():
    print(f"  line={sp}  ({int(sp) / 240:.2f} 倍)  {n} 处")

print()
print("=== 5. 表格数量 ===")
print("  <w:tbl>:", d.count("<w:tbl>"))
print("  表头重复设置 tblHeader:", d.count("<w:tblHeader"))
print("  行不跨页 cantSplit:", d.count("<w:cantSplit"))
