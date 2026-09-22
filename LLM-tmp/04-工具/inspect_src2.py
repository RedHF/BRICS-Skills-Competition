# -*- coding: utf-8 -*-
"""List ALL source parts + sectPr of source document.xml."""
import zipfile

SRC = r"C:\Users\21178\Desktop\files\BRICS-Skills-Competition\Task01\Original\正式成果\2026-08-28-《檐下千秋》游戏策划案.docx"

with zipfile.ZipFile(SRC) as z:
    print("ALL PARTS:")
    for n in z.namelist():
        info = z.getinfo(n)
        print(f"  {n}  ({info.file_size} B)")
    doc = z.read('word/document.xml').decode('utf-8', errors='replace')
    # find sectPr
    import re
    m = re.search(r'<w:sectPr.*?</w:sectPr>', doc, re.DOTALL)
    print("\nSOURCE sectPr:\n", m.group(0) if m else "NOT FOUND")
