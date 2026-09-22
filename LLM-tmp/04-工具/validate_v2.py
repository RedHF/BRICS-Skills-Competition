# -*- coding: utf-8 -*-
"""Validate v2 docx: XML well-formedness, footnote refs (one per keyword), margins, heading cleanup."""
import zipfile
from xml.etree import ElementTree as ET

PATH = r"C:\Users\21178\Desktop\files\BRICS-Skills-Competition\《檐下千秋》游戏策划案（正式文案·临时稿v2）.docx"
W = '{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'

with zipfile.ZipFile(PATH) as z:
    names = z.namelist()
    print("PARTS (%d):" % len(names))
    for n in names:
        print("  ", n)
    bad = 0
    for n in names:
        if n.endswith(('.xml', '.rels')):
            try:
                ET.fromstring(z.read(n))
            except Exception as e:
                bad += 1
                print("XML FAIL", n, e)
    print("XML parse failures:", bad)

    doc = ET.fromstring(z.read('word/document.xml'))
    fn = ET.fromstring(z.read('word/footnotes.xml'))

    refs = [int(r.get(W+'id')) for r in doc.iter(W+'footnoteReference')]
    print("footnote refs in document:", len(refs), sorted(set(refs)))
    print("DUPLICATE refs:", sorted({r for r in refs if refs.count(r) > 1}) or "none")

    fn_ids = sorted(int(f.get(W+'id')) for f in fn.iter(W+'footnote') if int(f.get(W+'id')) > 0)
    print("footnote ids defined:", fn_ids)
    print("missing:", sorted(set(refs) - set(fn_ids)) or "none")

    blue = [r for r in doc.iter(W+'color') if r.get(W+'val') == '0000FF']
    print("blue keyword runs:", len(blue))

    for s in doc.iter(W+'pgMar'):
        print("margins (twips): top=%s bottom=%s left=%s right=%s" % (
            s.get(W+'top'), s.get(W+'bottom'), s.get(W+'left'), s.get(W+'right')))

    # heading check: collect heading texts (black font, bold, 32 or 28)
    texts = []
    for p in doc.iter(W+'p'):
        t = "".join(x.text or "" for x in p.iter(W+'t'))
        if t.strip():
            texts.append(t.strip())
    hits = [t for t in texts if '评分点' in t]
    print("headings/texts containing '评分点':", hits if hits else "NONE (ok)")
    print("total paragraphs with text:", len(texts))
    print("tables:", len(list(doc.iter(W+'tbl'))))
