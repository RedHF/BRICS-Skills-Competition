# -*- coding: utf-8 -*-
"""Inspect source docx parts so we can reuse its infrastructure as a skeleton."""
import zipfile

SRC = r"C:\Users\21178\Desktop\files\BRICS-Skills-Competition\Task01\Original\正式成果\2026-08-28-《檐下千秋》游戏策划案.docx"

with zipfile.ZipFile(SRC) as z:
    for n in z.namelist():
        data = z.read(n)
        if n.endswith(('.rels', '[Content_Types].xml', 'footer1.xml', 'settings.xml')):
            print("=" * 30, n, "=" * 30)
            print(data.decode('utf-8', errors='replace')[:3000])
