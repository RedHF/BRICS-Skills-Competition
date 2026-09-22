# -*- coding: utf-8 -*-
"""Extract paragraph text from a .docx (zip of OOXML parts) using only stdlib."""
import zipfile
import sys
from xml.etree import ElementTree as ET

W = '{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'

def extract(path, out_path):
    with zipfile.ZipFile(path) as z:
        names = z.namelist()
        print("PARTS:", [n for n in names if n.startswith('word/')])
        xml = z.read('word/document.xml')

    root = ET.fromstring(xml)
    lines = []
    for para in root.iter(W + 'p'):
        texts = []
        for node in para.iter():
            if node.tag == W + 't':
                texts.append(node.text or '')
            elif node.tag == W + 'tab':
                texts.append('\t')
            elif node.tag == W + 'br':
                texts.append('\n')
        lines.append(''.join(texts))

    # also capture tables (paragraphs inside table cells are already in the p loop
    # since iter() walks the whole tree; but table cell boundaries add no marker,
    # so append a pipe when a cell ends)
    text = '\n'.join(lines)
    print("TOTAL CHARS:", len(text))
    with open(out_path, 'w', encoding='utf-8') as f:
        f.write(text)
    print("DUMPED ->", out_path)

if __name__ == '__main__':
    extract(sys.argv[1], sys.argv[2])
