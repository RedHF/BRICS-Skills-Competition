# -*- coding: utf-8 -*-
"""Validate the generated docx: XML well-formedness + footnote ref integrity."""
import zipfile
from xml.etree import ElementTree as ET

PATH = r"C:\Users\21178\Desktop\files\BRICS-Skills-Competition\《檐下千秋》游戏策划案（正式文案·临时稿）.docx"
W = '{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'

with zipfile.ZipFile(PATH) as z:
    names = z.namelist()
    print("PARTS:", names)
    for n in names:
        if n.endswith('.xml') or n.endswith('.rels'):
            data = z.read(n)
            try:
                ET.fromstring(data)
                print(f"OK   {n}")
            except Exception as e:
                print(f"FAIL {n}: {e}")

    # footnote integrity
    doc = ET.fromstring(z.read('word/document.xml'))
    fn = ET.fromstring(z.read('word/footnotes.xml'))
    refs = [int(r.get(W+'id')) for r in doc.iter(W+'footnoteReference')]
    fn_ids = set()
    for f in fn.iter(W+'footnote'):
        fid = int(f.get(W+'id'))
        if fid > 0:
            fn_ids.add(fid)
    print("footnote refs used:", sorted(set(refs)))
    print("footnote ids defined (positive):", sorted(fn_ids))
    missing = [r for r in refs if r not in fn_ids]
    print("MISSING footnote ids:", missing if missing else "none")
    # count blue keywords
    blue = [r for r in doc.iter(W+'color') if r.get(W+'val') == '0000FF']
    print("blue keyword runs:", len(blue))
    # margins
    for s in doc.iter(W+'pgMar'):
        print("margins (twips): top=%s bottom=%s left=%s right=%s" % (
            s.get(W+'top'), s.get(W+'bottom'), s.get(W+'left'), s.get(W+'right')))
    # count tables
    print("tables:", len(list(doc.iter(W+'tbl'))))
