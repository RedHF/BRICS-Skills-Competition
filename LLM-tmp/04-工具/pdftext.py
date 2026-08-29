# -*- coding: utf-8 -*-
"""Minimal pure-stdlib PDF text extractor for text-based PDFs (CID fonts + ToUnicode).
Usage: python pdftext.py <idx> info | <idx> <page> [page2] | <idx> all
"""
import zlib, re, os, sys

D = r"C:\Users\Admin\Documents\GitHub\BRICS-Skills-Competition\Official_Document"
FILES = sorted(f for f in os.listdir(D) if f.endswith(".pdf"))


def get_objects(data):
    objs = {}
    for m in re.finditer(rb"(\d+)\s+0\s+obj\b(.*?)endobj", data, re.DOTALL):
        objs[int(m.group(1))] = m.group(2)
    return objs


def get_stream(body):
    m = re.search(rb"stream\r?\n(.*?)endstream", body, re.DOTALL)
    if not m:
        return None
    s = m.group(1)
    if s.startswith(b"\r\n"):
        s = s[2:]
    elif s.startswith(b"\n") or s.startswith(b"\r"):
        s = s[1:]
    try:
        return zlib.decompress(s)
    except Exception:
        return s


def parse_cmap(body):
    cmap = {}
    cs = 1
    stream = get_stream(body) or b""
    m = re.search(rb"begincodespacerange\s*(.*?)endcodespacerange", stream, re.DOTALL)
    if m:
        m2 = re.search(rb"<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>", m.group(1))
        if m2:
            cs = len(m2.group(1)) // 2
    for m in re.finditer(rb"beginbfchar\s*(.*?)endbfchar", stream, re.DOTALL):
        for line in m.group(1).splitlines():
            mm = re.match(rb"\s*<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*$", line)
            if mm:
                try:
                    dst = bytes.fromhex(mm.group(2).decode()).decode("utf-16-be")
                    cmap[bytes.fromhex(mm.group(1).decode())] = dst
                except Exception:
                    pass
    for m in re.finditer(rb"beginbfrange\s*(.*?)endbfrange", stream, re.DOTALL):
        for line in m.group(1).splitlines():
            line = line.strip()
            mm = re.match(rb"<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*$", line)
            if mm:
                lo = int(mm.group(1), 16)
                hi = int(mm.group(2), 16)
                st = int(mm.group(3), 16)
                if hi - lo > 50000:
                    continue
                for c in range(lo, hi + 1):
                    try:
                        cmap[c.to_bytes(cs, "big")] = chr(st + (c - lo))
                    except Exception:
                        pass
                continue
            mm = re.match(rb"<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*\[(.*)\]\s*$", line)
            if mm:
                lo = int(mm.group(1), 16)
                hi = int(mm.group(2), 16)
                dsts = re.findall(rb"<([0-9A-Fa-f]+)>", mm.group(3))
                for i, c in enumerate(range(lo, hi + 1)):
                    if i >= len(dsts):
                        break
                    try:
                        cmap[c.to_bytes(cs, "big")] = bytes.fromhex(dsts[i].decode()).decode("utf-16-be")
                    except Exception:
                        pass
    return cmap, cs


def find_pages(objs):
    pages = []

    def walk(n, depth=0):
        if depth > 15 or n not in objs:
            return
        body = objs[n]
        if re.search(rb"/Type\s*/\s*Page\b", body):
            pages.append((n, body))
            return
        if re.search(rb"/Type\s*/\s*Pages\b", body):
            for m in re.finditer(rb"(\d+)\s+0\s+R", body):
                walk(int(m.group(1)), depth + 1)

    for n, b in list(objs.items()):
        if re.search(rb"/Type\s*/\s*Pages\b", b):
            walk(n)
    seen = set()
    out = []
    for p in pages:
        if p[0] not in seen:
            seen.add(p[0])
            out.append(p)
    if not out:
        out = [(n, b) for n, b in objs.items() if re.search(rb"/Type\s*/\s*Page\b", b)]
    return out


def font_cmaps(objs):
    fm = {}
    for n, body in objs.items():
        if re.search(rb"/Type\s*/\s*Font\b", body):
            m = re.search(rb"/ToUnicode\s+(\d+)\s+0\s+R", body)
            if m:
                tgt = int(m.group(1))
                if tgt in objs:
                    cmap, cs = parse_cmap(objs[tgt])
                    if cmap:
                        fm[n] = (cmap, cs)
    return fm


def decode_lit(s):
    s = s[1:-1]

    def rep(m):
        c = m.group(1)
        if c in b"nrtbf":
            return {b"n": "\n", b"r": "\r", b"t": "\t", b"b": "\b", b"f": "\f"}[c]
        if c in b"()\\":
            return c.decode()
        if re.match(rb"[0-7]{1,3}$", c):
            return chr(int(c, 8))
        return ""

    return re.sub(rb"\\([0-7]{1,3}|.)", rep, s).decode("latin-1", "replace")


def decode_hex(h, cmap, cs):
    h = h.strip()
    if h[:1] == b"<":
        h = h[1:]
    if h[-1:] == b">":
        h = h[:-1]
    hx = re.sub(rb"\s", b"", h)
    try:
        raw = bytes.fromhex(hx.decode("ascii"))
    except Exception:
        return ""
    out = []
    pos = 0
    while pos < len(raw):
        found = False
        for L in range(min(4, len(raw) - pos), 0, -1):
            key = raw[pos:pos + L]
            if key in cmap:
                out.append(cmap[key])
                pos += L
                found = True
                break
        if not found:
            out.append("?")
            pos += max(1, cs)
    return "".join(out)


TOKEN = re.compile(
    rb"""<<[^>]*>>|\[[^\[\]]*\]|\((?:\\.|[^()\\])*\)|<[0-9A-Fa-f\s]*[0-9A-Fa-f][0-9A-Fa-f\s]*>|-?(?:\d+\.?\d*|\.\d+)|[A-Za-z0-9*/+.#$_-]+|['"]""",
    re.VERBOSE,
)


def is_operand(t):
    if re.match(rb"-?(?:\d+\.?\d*|\.\d+)$", t):
        return True
    if t[:1] in (b"<", b"(", b"[", b"/"):
        return True
    return False


def page_text(objs, fonts, body):
    cm = re.search(rb"/Contents\s+(\d+)\s+0\s+R", body)
    if not cm:
        return ""
    refs = [cm.group(1)]
    arr = re.search(rb"/Contents\s*\[([^\]]*)\]", body)
    if arr:
        refs = re.findall(rb"(\d+)\s+0\s+R", arr.group(1))
    chunks = []
    for cn in refs:
        if int(cn) not in objs:
            continue
        st = get_stream(objs[int(cn)])
        if not st:
            continue
        tokens = TOKEN.findall(st)
        stack = []
        x = 0.0
        y = 0.0
        size = 10.0
        leading = 12.0
        curf = None
        sx = 1.0

        def resolve_font(name):
            mm = re.match(rb"/?([A-Za-z0-9]+)$", name)
            if not mm:
                return None
            key = mm.group(1).decode()
            rm = re.search(rb"/Font\s*<<(.*?)>>", body)
            if rm:
                fm2 = re.search(rb"/" + re.escape(key.encode()) + rb"\s+(\d+)\s+0\s+R", rm.group(1))
                if fm2 and int(fm2.group(1)) in fonts:
                    return int(fm2.group(1))
            return None

        def show(s):
            nonlocal x, y
            f = fonts.get(curf) if isinstance(curf, int) else None
            if f:
                txt = decode_hex(s, f[0], f[1]) if s[:1] == b"<" else decode_lit(s)
            else:
                txt = ""
            if txt:
                chunks.append((x, y, txt))

        for t in tokens:
            if is_operand(t):
                stack.append(t)
                continue
            if t == b"Tj" and stack:
                show(stack[-1])
            elif t == b"TJ" and stack:
                arr = stack[-1]
                f = fonts.get(curf) if isinstance(curf, int) else None
                for item in re.findall(
                    rb"<[0-9A-Fa-f\s]*[0-9A-Fa-f][0-9A-Fa-f\s]*>|\((?:\\.|[^()\\])*\)|-?\d+\.?\d*", arr
                ):
                    if re.match(rb"-?\d", item):
                        x -= float(item) * size / 1000.0 * sx
                    elif f:
                        txt = decode_hex(item, f[0], f[1]) if item[:1] == b"<" else decode_lit(item)
                        if txt:
                            chunks.append((x, y, txt))
            elif t == b"'" and stack:
                y -= leading * sx
                show(stack[-1])
            elif t == b'"' and len(stack) >= 3:
                y -= leading * sx
                show(stack[-3])
            elif t == b"Tm" and len(stack) >= 6:
                x = float(stack[-2])
                y = float(stack[-1])
                a = abs(float(stack[-6]))
                if a > 0:
                    sx = a
            elif t in (b"Td", b"TD") and len(stack) >= 2:
                ty = float(stack[-1])
                tx = float(stack[-2])
                x += tx * sx
                y += ty * sx
                if t == b"TD":
                    leading = abs(ty)
            elif t == b"T*":
                y -= leading * sx
            elif t == b"Tf" and len(stack) >= 2:
                size = float(stack[-1])
                curf = resolve_font(stack[-2])
            elif t == b"BT":
                x = y = 0.0
                sx = 1.0
            stack.clear()
    if not chunks:
        return ""
    chunks.sort(key=lambda c: (-round(c[1] * 4) / 4, c[0]))
    lines = []
    cur_y = None
    cur_line = ""
    for cx, cy, txt in chunks:
        if cur_y is None or abs(cy - cur_y) > 3.0:
            if cur_line:
                lines.append(cur_line)
            cur_y = cy
            cur_line = txt
        else:
            if cur_line and cur_line[-1].isascii() and txt[0].isascii() and cur_line[-1].isalnum() and txt[0].isalnum():
                cur_line += " "
            cur_line += txt
    if cur_line:
        lines.append(cur_line)
    return "\n".join(lines)


def main():
    if len(sys.argv) < 2:
        for i, f in enumerate(FILES):
            print(f"[{i}] {f}")
        print("usage: pdftext.py <idx> info | <idx> <page> [page2] | <idx> all")
        return
    idx = int(sys.argv[1])
    data = open(os.path.join(D, FILES[idx]), "rb").read()
    objs = get_objects(data)
    fonts = font_cmaps(objs)
    pages = find_pages(objs)
    if len(sys.argv) >= 3 and sys.argv[2] == "info":
        print("file:", FILES[idx], "| pages:", len(pages), "| fonts:", len(fonts))
        for pi, (n, body) in enumerate(pages, 1):
            t = page_text(objs, fonts, body)
            prev = t.replace("\n", " / ")[:120]
            print(f"--- p{pi}: {prev}")
        return
    if len(sys.argv) >= 3 and sys.argv[2] == "all":
        lo, hi = 1, len(pages)
    else:
        lo = int(sys.argv[2]) if len(sys.argv) >= 3 else 1
        hi = int(sys.argv[3]) if len(sys.argv) >= 4 else lo
    for pi, (n, body) in enumerate(pages, 1):
        if pi < lo or pi > hi:
            continue
        print(f"\n===== file[{idx}] page {pi} =====\n")
        print(page_text(objs, fonts, body))


if __name__ == "__main__":
    main()
