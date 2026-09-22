# -*- coding: utf-8 -*-
"""核验：每个关键词是否「全文蓝色高亮，但脚注只标一次」。"""
import re
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
P = ROOT / "《檐下千秋》游戏策划案（正式稿）.docx"
z = zipfile.ZipFile(P)
d = z.read("word/document.xml").decode("utf-8")
f = z.read("word/footnotes.xml").decode("utf-8")

KWS = ["墨灵", "白蚀", "心舍", "墨痕", "侵蚀度", "拓印", "记忆账册", "檐下谱",
       "建筑意", "无我识海", "墨灵符诏", "识海", "榫卯", "斗拱", "飞檐", "藻井",
       "通天塔", "回溯"]

BLUE_RUN = '<w:color w:val="0000FF"/>'
FOOT_RUN = '</w:r><w:r><w:rPr><w:rStyle w:val="FootnoteReference"/></w:rPr><w:footnoteReference'

print(f"{'关键词':<10}{'蓝色高亮':>10}{'脚注引用':>10}")
tb = tf = 0
bad = []
for k in KWS:
    n_blue = len(re.findall(
        re.escape(BLUE_RUN) + r'(?:(?!</w:r>).)*?<w:t[^>]*>' + re.escape(k) + r'</w:t>', d))
    n_ref = len(re.findall(
        r'<w:t[^>]*>' + re.escape(k) + r'</w:t>' + re.escape(FOOT_RUN), d))
    tb += n_blue
    tf += n_ref
    flag = ""
    if n_ref > 1:
        flag = "  <== 脚注重复！"
        bad.append(k)
    print(f"{k:<10}{n_blue:>10}{n_ref:>10}{flag}")

print()
print(f"{'合计':<10}{tb:>10}{tf:>10}")
print("document.xml 脚注引用总数:", d.count("<w:footnoteReference"))
print("footnotes.xml 脚注定义数:", len(re.findall(r'<w:footnote w:id="[1-9]', f)))
print("嵌入图片:", [n.split("/")[-1] for n in z.namelist() if n.startswith("word/media/")])
print()
print("结论:", "全部关键词均只标一次脚注 ✓" if not bad else f"以下关键词重复标注：{bad}")
