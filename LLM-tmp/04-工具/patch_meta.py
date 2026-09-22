# -*- coding: utf-8 -*-
"""Patch docProps/core.xml metadata in the v2 docx."""
import os
import zipfile

P = r"C:\Users\21178\Desktop\files\BRICS-Skills-Competition\《檐下千秋》游戏策划案（正式文案·临时稿v2）.docx"

core = (
    "<?xml version='1.0' encoding='UTF-8' standalone='yes'?>\n"
    '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
    'xmlns:dc="http://purl.org/dc/elements/1.1/" '
    'xmlns:dcterms="http://purl.org/dc/terms/" '
    'xmlns:dcmitype="http://purl.org/dc/dcmitype/" '
    'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
    '<dc:title>《檐下千秋》游戏策划案（正式文案·临时稿）</dc:title>'
    '<dc:subject>AI 赋能数字创意设计与应用赛项 Task01 游戏策划案</dc:subject>'
    '<dc:creator>BRICS 参赛团队</dc:creator>'
    '<cp:keywords>檐下千秋,游戏策划案,文化传承,数字再造</cp:keywords>'
    '<dc:description>依据 BRICS2026 赛题赛道一 Task01 要求撰写的正式游戏策划案</dc:description>'
    '<cp:lastModifiedBy>DeepSeek Harness</cp:lastModifiedBy>'
    '<cp:revision>2</cp:revision>'
    '<dcterms:created xsi:type="dcterms:W3CDTF">2026-08-30T00:00:00Z</dcterms:created>'
    '<dcterms:modified xsi:type="dcterms:W3CDTF">2026-08-30T00:00:00Z</dcterms:modified>'
    "</cp:coreProperties>"
)

with zipfile.ZipFile(P) as z:
    items = [(i, z.read(i.filename)) for i in z.infolist()]

tmp = P + ".tmp"
with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as z:
    for info, data in items:
        if info.filename == "docProps/core.xml":
            data = core.encode("utf-8")
        z.writestr(info, data)
os.replace(tmp, P)
print("core.xml patched OK")
