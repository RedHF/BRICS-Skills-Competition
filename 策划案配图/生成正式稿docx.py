# -*- coding: utf-8 -*-
"""把《檐下千秋》游戏策划案（正式稿）.md 生成为符合 BRICS2026 Task01 排版要求的 docx。

排版标准（全篇统一）：
- 封面页：作品名称 / 队伍 ID / 日期
- 标题：黑体加粗，一级三号（32 半磅），二级小三（30 半磅）
- 正文：宋体小四（24 半磅）、1.5 倍行距（w:line=360）
- 表格：宋体小四；表头黑体小四加粗、浅底纹、跨页重复
- 关键词：全文蓝色高亮（0000FF），脚注只在首次出现时标注
- 页边距：2.54cm（1440 twips）

纯标准库实现（zipfile + 手写 OOXML）；图片尺寸用 PIL 读取。
所有文本一律经 render_text 渲染，杜绝 Markdown 记号泄漏到 docx。
"""
import re
import zipfile
from pathlib import Path
from xml.sax.saxutils import escape

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
DOC_DIR = ROOT / "Task01" / "Original" / "正式成果"
SRC = DOC_DIR / "《檐下千秋》游戏策划案（正式稿）.md"
OUT = DOC_DIR / "《檐下千秋》游戏策划案（正式稿）.docx"

# ---------------------------------------------------------------- 字体常量
F_TITLE = "黑体"      # 标题
F_BODY = "宋体"       # 正文、表格、引用、图注
SZ_H1 = 32            # 三号 16pt
SZ_H2 = 30            # 小三 15pt
SZ_BODY = 24          # 小四 12pt
SZ_FOOT = 18          # 小五 9pt（脚注）
SZ_COVER_T = 52       # 封面主标题
SZ_COVER_S = 36       # 封面副标题
LINE_BODY = "360"     # 1.5 倍行距
LINE_TABLE = "240"    # 单倍行距（表格内）
SHADE_HEAD = "E8EDEB"  # 表头底纹

# ---- 封面信息（队伍确认后修改这里即可） ----
COVER = {
    "作品名称": "《檐下千秋》",
    "队伍 ID": "【待确认】",
    "组别": "【待确认】",
    "日期": "2026 年 9 月",
    "subtitle": "依据 2026 一带一路暨金砖国家技能发展与技术创新大赛\n"
                "首届 AI 赋能数字创意设计与应用赛项\n"
                "赛道一（交互赛道·小游戏开发）Task01 要求编制",
}

# ---- 关键词 -> 脚注解释（全文蓝色高亮；脚注只在首次出现时标注） ----
KEYWORDS = {
    "墨灵": "由古建承载的「匠魂之忆」（情感、秘闻、失传技艺等）凝结而成的记忆灵质，肉眼不可见，是世界观中的核心概念。",
    "白蚀": "由「遗忘」逆结晶而成的侵蚀现象，被侵蚀的古建会褪色失忆；它是「被遗忘」的具象化，对抗白蚀即对抗遗忘。",
    "心舍": "主角承载墨灵符诏的背包系统，即「识海」；容量初始 5 道、上限 7 道墨灵，拓印新记忆需抹去旧记忆。",
    "墨痕": "游戏内唯一的进度资源，无传统货币；按事件星级（1–3 星）发放，用于回溯重试。",
    "侵蚀度": "替代生命值的失败风险条（0–100），非描摹谜题失败 +10、受击 +5、战败 +15，达 100 时本次事件失败。",
    "拓印": "本作核心操作机制，沿墨线容差带逐笔重现刻字，将古建记忆复写为墨灵符诏；兼具解谜工具与战斗技艺双重用途。",
    "记忆账册": "记录玩家「记住/遗忘」抉择的叙事档案，可在底部导航随时查看，形成玩家专属的叙事档案。",
    "檐下谱": "主角持有的空白册子，既是叙事旁白声部，也是记忆账册的人格化载体。",
    "建筑意": "世界观核心设定：墨痕王朝依赖建筑承载的「意」维系文明，分技艺之忆（构件）、仪礼之忆（空间）、情感之忆（器物）三级结构。",
    "无我识海": "主角因失忆而具备的空白识海，是承载他人记忆的资格条件；空白《檐下谱》与空白识海互为表里。",
    "墨灵符诏": "拓印所得的记忆载体，兼具解谜工具与战斗技艺双重用途（斗拱=承重/护盾，飞檐=远程，藻井=净化）。",
    "识海": "即「心舍」，承载墨灵的背包空间；容量越高，自身记忆越被稀释——「记别人的事，就会忘自己的事」。",
    "榫卯": "中国传统木构建筑的接合方式，本作构件归位谜题的文化原型。",
    "斗拱": "中国传统建筑承重构件，本作中对应「承重/护盾」技艺。",
    "飞檐": "中国传统建筑屋檐构件，本作中对应「远程/延伸」技艺。",
    "藻井": "中国传统建筑顶部装饰构件，本作中对应「净化/清明」技艺。",
    "通天塔": "皇城中的七层高塔，终局场景；与识海上限 7 格形成回环。",
    "回溯": "失败后消耗 1 墨痕（墨痕为 0 时免费）回到事件起点的机制，保留已获墨灵、技艺与已确认的取舍。",
}
KW_SPLIT = re.compile(
    "(" + "|".join(re.escape(k) for k in sorted(KEYWORDS, key=len, reverse=True)) + ")")

EMU_PER_INCH = 914400
PAGE_W_TW = 11906
MARGIN_TW = 1440
CONTENT_TW = PAGE_W_TW - MARGIN_TW * 2          # = 9026 twips
MAX_W_EMU = int(CONTENT_TW / 1440 * EMU_PER_INCH)
MAX_H_EMU = int(6.8 * EMU_PER_INCH)


def esc(t):
    return escape(t, {'"': "&quot;"})


def strip_markdown(t):
    """兜底：清除任何漏网的 Markdown 记号。"""
    t = t.replace("{{", "").replace("}}", "")
    t = re.sub(r"\*\*(.+?)\*\*", r"\1", t)
    t = t.replace("**", "")
    return t


class Builder:
    def __init__(self):
        self.body = []
        self.footnotes = []
        self.footnote_id_of = {}
        self.images = []

    # ---------------------------------------------------------------- run
    def run(self, text, font=F_BODY, size=SZ_BODY, bold=False, color=None, footnote=None):
        text = strip_markdown(text)
        if not text:
            return ""
        rpr = [f'<w:rFonts w:ascii="{font}" w:eastAsia="{font}" w:hAnsi="{font}"/>']
        if bold:
            rpr.append("<w:b/>")
        if color:
            rpr.append(f'<w:color w:val="{color}"/>')
        rpr.append(f'<w:sz w:val="{size}"/><w:szCs w:val="{size}"/>')
        r = f'<w:r><w:rPr>{"".join(rpr)}</w:rPr><w:t xml:space="preserve">{esc(text)}</w:t></w:r>'
        if footnote is not None:
            r += (f'<w:r><w:rPr><w:rStyle w:val="FootnoteReference"/></w:rPr>'
                  f'<w:footnoteReference w:id="{footnote}"/></w:r>')
        return r

    def para(self, runs, ppr=""):
        inner = "".join(runs) if isinstance(runs, list) else runs
        return f"<w:p>{ppr}{inner}</w:p>"

    # ------------------------------------------------- 关键词：高亮 + 首现脚注
    def emit_kw(self, runs, kw, bold, size):
        fid = None
        if kw in KEYWORDS and kw not in self.footnote_id_of:
            fid = len(self.footnotes) + 1
            self.footnote_id_of[kw] = fid
            self.footnotes.append(KEYWORDS[kw])
        runs.append(self.run(kw, size=size, bold=bold, color="0000FF", footnote=fid))

    def render_text(self, text, base_bold=False, size=SZ_BODY):
        """唯一文本渲染入口：处理 **粗体** 与关键词高亮。"""
        runs = []
        for seg in re.split(r"(\*\*.+?\*\*)", strip_markdown(text)):
            if not seg:
                continue
            bold = base_bold
            m = re.fullmatch(r"\*\*(.+?)\*\*", seg, re.S)
            if m:
                seg, bold = m.group(1), True
            for tok in KW_SPLIT.split(seg):
                if not tok:
                    continue
                if tok in KEYWORDS:
                    self.emit_kw(runs, tok, bold, size)
                else:
                    runs.append(self.run(tok, size=size, bold=bold))
        return runs or [self.run(" ", size=size)]

    # ---------------------------------------------------------------- 段落
    def body_para(self, text):
        ppr = (f'<w:pPr><w:spacing w:line="{LINE_BODY}" w:lineRule="auto"/>'
               '<w:ind w:firstLineChars="200" w:firstLine="480"/></w:pPr>')
        return self.para(self.render_text(text), ppr)

    def heading(self, text, level=1):
        sz = SZ_H1 if level == 1 else SZ_H2
        ppr = (f'<w:pPr><w:spacing w:before="240" w:after="120" w:line="{LINE_BODY}" '
               'w:lineRule="auto"/>')
        if level == 1:
            ppr += '<w:jc w:val="center"/>'
        ppr += f'<w:outlineLvl w:val="{level - 1}"/></w:pPr>'
        return self.para([self.run(text, font=F_TITLE, size=sz, bold=True)], ppr)

    def list_para(self, text, ordered=False, idx=0):
        ppr = (f'<w:pPr><w:spacing w:line="{LINE_BODY}" w:lineRule="auto"/>'
               '<w:ind w:leftChars="200" w:left="480" w:hangingChars="100" w:hanging="240"/></w:pPr>')
        prefix = f"{idx}. " if ordered else "· "
        return self.para([self.run(prefix)] + self.render_text(text), ppr)

    def quote_para(self, text):
        """引用段落：宋体小四、缩进，规范与正文一致。"""
        ppr = (f'<w:pPr><w:spacing w:line="{LINE_BODY}" w:lineRule="auto"/>'
               '<w:ind w:leftChars="200" w:left="480"/></w:pPr>')
        return self.para(self.render_text(text), ppr)

    def code_para(self, text):
        """流程图/公式块：宋体小四、缩进，不使用等宽字体。"""
        ppr = (f'<w:pPr><w:spacing w:line="{LINE_BODY}" w:lineRule="auto"/>'
               '<w:ind w:leftChars="200" w:left="480"/></w:pPr>')
        return self.para(self.render_text(text), ppr)

    def caption(self, text):
        ppr = (f'<w:pPr><w:spacing w:after="200" w:line="{LINE_BODY}" w:lineRule="auto"/>'
               '<w:jc w:val="center"/></w:pPr>')
        return self.para(self.render_text(text), ppr)

    # ---------------------------------------------------------------- 表格
    def table(self, header, rows):
        n = len(header)
        # 按各列最长内容自动分配列宽，避免某列被挤成一字一行
        def visual(s):
            return sum(2 if ord(c) > 0x2000 else 1 for c in s)

        wid = []
        for c in range(n):
            cells = [header[c]] + [r[c] if c < len(r) else "" for r in rows]
            wid.append(max(6, min(34, max(visual(x) for x in cells))))
        scale = CONTENT_TW / sum(wid)
        cols = [max(560, int(w * scale)) for w in wid]
        fix = CONTENT_TW - sum(cols)
        cols[-1] += fix

        grid = "".join(f'<w:gridCol w:w="{w}"/>' for w in cols)
        borders = "".join(
            f'<w:{b} w:val="single" w:sz="4" w:space="0" w:color="BFCBC6"/>'
            for b in ("top", "left", "bottom", "right", "insideH", "insideV"))
        tblpr = (
            '<w:tblPr><w:tblStyle w:val="TableGrid"/>'
            '<w:tblW w:w="5000" w:type="pct"/><w:jc w:val="center"/>'
            f'<w:tblBorders>{borders}</w:tblBorders>'
            '<w:tblLayout w:type="fixed"/>'
            '<w:tblCellMar><w:top w:w="70" w:type="dxa"/><w:left w:w="110" w:type="dxa"/>'
            '<w:bottom w:w="70" w:type="dxa"/><w:right w:w="110" w:type="dxa"/></w:tblCellMar>'
            '</w:tblPr>')

        def cell(content, w, header_cell=False):
            tcpr = f'<w:tcPr><w:tcW w:w="{w}" w:type="dxa"/>'
            if header_cell:
                tcpr += f'<w:shd w:val="clear" w:color="auto" w:fill="{SHADE_HEAD}"/>'
            tcpr += '<w:vAlign w:val="center"/></w:tcPr>'
            ppr = (f'<w:pPr><w:spacing w:before="20" w:after="20" w:line="{LINE_TABLE}" '
                   'w:lineRule="auto"/><w:jc w:val="left"/></w:pPr>')
            if header_cell:
                runs = [self.run(content, font=F_TITLE, size=SZ_BODY, bold=True)]
            else:
                runs = self.render_text(content)
            return f'<w:tc>{tcpr}{self.para(runs, ppr)}</w:tc>'

        out = ['<w:tr><w:trPr><w:cantSplit/><w:tblHeader/></w:trPr>'
               + "".join(cell(header[i], cols[i], True) for i in range(n)) + "</w:tr>"]
        for r in rows:
            out.append("<w:tr><w:trPr><w:cantSplit/></w:trPr>"
                       + "".join(cell(r[i] if i < len(r) else "", cols[i]) for i in range(n))
                       + "</w:tr>")
        tbl = f'<w:tbl>{tblpr}<w:tblGrid>{grid}</w:tblGrid>{"".join(out)}</w:tbl>'
        # 表后留一个空段，避免两表粘连
        return tbl + f'<w:p><w:pPr><w:spacing w:after="0" w:line="{LINE_TABLE}"/></w:pPr></w:p>'

    # ---------------------------------------------------------------- 图片
    def image(self, path):
        with Image.open(path) as im:
            iw, ih = im.size
        scale = min(MAX_W_EMU / iw, MAX_H_EMU / ih)
        cx, cy = int(iw * scale), int(ih * scale)
        rid = len(self.images) + 1
        self.images.append((rid, path))
        docid = rid + 100
        drawing = (
            '<w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0">'
            f'<wp:extent cx="{cx}" cy="{cy}"/><wp:effectExtent l="0" t="0" r="0" b="0"/>'
            f'<wp:docPr id="{docid}" name="Picture {docid}"/>'
            '<wp:cNvGraphicFramePr><a:graphicFrameLocks '
            'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" noChangeAspect="1"/>'
            '</wp:cNvGraphicFramePr>'
            '<a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
            '<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
            '<pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
            f'<pic:nvPicPr><pic:cNvPr id="{docid}" name="Picture {docid}"/><pic:cNvPicPr/></pic:nvPicPr>'
            f'<pic:blipFill><a:blip r:embed="rIdImg{rid}"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
            '<pic:spPr><a:xfrm><a:off x="0" y="0"/>'
            f'<a:ext cx="{cx}" cy="{cy}"/></a:xfrm>'
            '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
            '</pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>')
        return self.para([drawing], '<w:pPr><w:jc w:val="center"/></w:pPr>')

    def spacer(self, n=1):
        for _ in range(n):
            self.body.append('<w:p><w:pPr><w:spacing w:after="0"/></w:pPr></w:p>')


# --------------------------------------------------------------------------
def parse(md_lines):
    b = Builder()
    intro = []
    i, n = 0, len(md_lines)
    while i < n and not md_lines[i].startswith("## "):
        ln = md_lines[i].strip()
        if ln.startswith(">"):
            intro.append(ln.lstrip("> ").strip())
        i += 1
    for s in intro:
        b.body.append(b.quote_para(s))
    b.spacer(1)

    in_code, buf = False, []
    while i < n:
        raw = md_lines[i].rstrip("\n")
        ln = raw.strip()
        i += 1

        if ln.startswith("```"):
            if in_code:
                for c in buf:
                    b.body.append(b.code_para(c))
                buf, in_code = [], False
            else:
                in_code = True
            continue
        if in_code:
            buf.append(raw)
            continue

        if not ln or ln == "---":
            continue

        m = re.fullmatch(r"!\[([^\]]*)\]\(([^)]+)\)", ln)
        if m:
            p = ROOT / m.group(2)
            if p.exists():
                b.body.append(b.image(p))
                b.body.append(b.caption("图　" + m.group(1) if m.group(1) else ""))
            else:
                b.body.append(b.body_para(f"[缺图：{m.group(2)}]"))
            continue

        if ln.startswith("### "):
            b.body.append(b.heading(ln[4:].strip(), 2))
            continue
        if ln.startswith("## "):
            b.body.append(b.heading(ln[3:].strip(), 1))
            continue
        if ln.startswith("# "):
            continue

        if ln.startswith("|"):
            block = [ln]
            while i < n and md_lines[i].strip().startswith("|"):
                block.append(md_lines[i].strip())
                i += 1
            rows = []
            for r in block:
                cells = [c.strip() for c in r.strip("|").split("|")]
                if all(re.fullmatch(r":?-{2,}:?", c) for c in cells if c):
                    continue
                rows.append(cells)
            if rows:
                b.body.append(b.table(rows[0], rows[1:]))
            continue

        if ln.startswith(">"):
            b.body.append(b.quote_para(ln.lstrip("> ").strip()))
            continue

        m = re.match(r"^[-*]\s+(.*)$", ln)
        if m:
            b.body.append(b.list_para(m.group(1)))
            continue
        m = re.match(r"^(\d+)[.、]\s+(.*)$", ln)
        if m:
            b.body.append(b.list_para(m.group(2), ordered=True, idx=int(m.group(1))))
            continue

        b.body.append(b.body_para(ln))
    return b


def build_footnotes(footnotes):
    parts = [
        '<w:footnote w:type="separator" w:id="-1"><w:p><w:pPr><w:spacing w:after="0" '
        'w:line="240" w:lineRule="auto"/></w:pPr><w:r><w:separator/></w:r></w:p></w:footnote>',
        '<w:footnote w:type="continuationSeparator" w:id="0"><w:p><w:pPr><w:spacing w:after="0" '
        'w:line="240" w:lineRule="auto"/></w:pPr><w:r><w:continuationSeparator/></w:r></w:p></w:footnote>',
    ]
    for i, t in enumerate(footnotes, start=1):
        parts.append(
            f'<w:footnote w:id="{i}"><w:p><w:pPr><w:spacing w:line="240" w:lineRule="auto"/></w:pPr>'
            f'<w:r><w:rPr><w:rStyle w:val="FootnoteReference"/></w:rPr><w:footnoteRef/></w:r>'
            f'<w:r><w:rPr><w:rFonts w:ascii="{F_BODY}" w:eastAsia="{F_BODY}" w:hAnsi="{F_BODY}"/>'
            f'<w:sz w:val="{SZ_FOOT}"/><w:szCs w:val="{SZ_FOOT}"/></w:rPr>'
            f'<w:t xml:space="preserve"> {esc(t)}</w:t></w:r></w:p></w:footnote>')
    return ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
            '<w:footnotes xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
            + "".join(parts) + "</w:footnotes>")


def cover_xml():
    def line(t, size, bold=False, fnt=F_BODY):
        return (f'<w:p><w:pPr><w:spacing w:line="{LINE_BODY}" w:lineRule="auto"/>'
                f'<w:jc w:val="center"/></w:pPr>'
                f'<w:r><w:rPr><w:rFonts w:ascii="{fnt}" w:eastAsia="{fnt}" w:hAnsi="{fnt}"/>'
                f'{"<w:b/>" if bold else ""}<w:sz w:val="{size}"/><w:szCs w:val="{size}"/></w:rPr>'
                f'<w:t xml:space="preserve">{esc(t)}</w:t></w:r></w:p>')

    out = ['<w:p><w:pPr><w:spacing w:line="360"/></w:pPr></w:p>'] * 3
    out.append(line("《檐下千秋》游戏策划案", SZ_COVER_T, True, F_TITLE))
    out.append(line("（正式稿）", SZ_COVER_S, True, F_TITLE))
    for _ in range(3):
        out.append(line("", SZ_BODY))
    for k in ("作品名称", "队伍 ID", "组别", "日期"):
        out.append(line(f"{k}：{COVER[k]}", SZ_H1))
    for _ in range(2):
        out.append(line("", SZ_BODY))
    for seg in COVER["subtitle"].split("\n"):
        out.append(line(seg, SZ_BODY))
    out.append('<w:p><w:r><w:br w:type="page"/></w:r></w:p>')
    return "".join(out)


def main():
    md = SRC.read_text(encoding="utf-8").splitlines()
    b = parse(md)

    document_xml = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
        'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        "<w:body>" + cover_xml() + "".join(b.body) +
        '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
        '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" '
        'w:header="851" w:footer="992" w:gutter="0"/>'
        '<w:cols w:space="425"/><w:docGrid w:type="lines" w:linePitch="312"/></w:sectPr>'
        "</w:body></w:document>")

    styles_xml = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:docDefaults><w:rPrDefault><w:rPr>'
        f'<w:rFonts w:ascii="{F_BODY}" w:eastAsia="{F_BODY}" w:hAnsi="{F_BODY}"/>'
        f'<w:sz w:val="{SZ_BODY}"/><w:szCs w:val="{SZ_BODY}"/></w:rPr></w:rPrDefault>'
        f'<w:pPrDefault><w:pPr><w:spacing w:line="{LINE_BODY}" w:lineRule="auto"/></w:pPr></w:pPrDefault>'
        '</w:docDefaults>'
        '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/>'
        f'<w:rPr><w:rFonts w:ascii="{F_BODY}" w:eastAsia="{F_BODY}" w:hAnsi="{F_BODY}"/>'
        f'<w:sz w:val="{SZ_BODY}"/><w:szCs w:val="{SZ_BODY}"/></w:rPr></w:style>'
        '<w:style w:type="character" w:styleId="FootnoteReference">'
        '<w:name w:val="footnote reference"/><w:rPr><w:vertAlign w:val="superscript"/></w:rPr></w:style>'
        '<w:style w:type="table" w:styleId="TableGrid"><w:name w:val="Table Grid"/>'
        f'<w:pPr><w:spacing w:line="{LINE_TABLE}" w:lineRule="auto"/></w:pPr><w:tblPr><w:tblBorders>'
        + "".join(f'<w:{x} w:val="single" w:sz="4" w:space="0" w:color="BFCBC6"/>'
                  for x in ("top", "left", "bottom", "right", "insideH", "insideV"))
        + '</w:tblBorders></w:tblPr></w:style></w:styles>')

    ct = ['<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
          '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
          '<Default Extension="xml" ContentType="application/xml"/>'
          '<Default Extension="png" ContentType="image/png"/>'
          '<Default Extension="jpg" ContentType="image/jpeg"/>'
          '<Default Extension="jpeg" ContentType="image/jpeg"/>'
          '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
          '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
          '<Override PartName="/word/footnotes.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footnotes+xml"/>'
          '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
          '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>'
          '</Types>']

    doc_rels = ['<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
                '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
                '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footnotes" Target="footnotes.xml"/>']
    for rid, p in b.images:
        doc_rels.append(f'<Relationship Id="rIdImg{rid}" '
                        f'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
                        f'Target="media/image{rid}{p.suffix.lower()}"/>')
    doc_rels.append("</Relationships>")

    root_rels = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
                 '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                 '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
                 '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
                 '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>'
                 '</Relationships>')

    core = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
            '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
            'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" '
            'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
            '<dc:title>《檐下千秋》游戏策划案（正式稿）</dc:title>'
            '<dc:creator>BRICS AI 赋能数字创意设计与应用赛项参赛团队</dc:creator>'
            '</cp:coreProperties>')
    app = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
           '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" '
           'xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">'
           '<Application>DeepSeek Harness</Application></Properties>')

    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", "".join(ct))
        z.writestr("_rels/.rels", root_rels)
        z.writestr("word/document.xml", document_xml)
        z.writestr("word/_rels/document.xml.rels", "".join(doc_rels))
        z.writestr("word/styles.xml", styles_xml)
        z.writestr("word/footnotes.xml", build_footnotes(b.footnotes))
        z.writestr("docProps/core.xml", core)
        z.writestr("docProps/app.xml", app)
        for rid, p in b.images:
            z.write(p, f"word/media/image{rid}{p.suffix.lower()}")

    print(f"SAVED: {OUT}")
    print(f"段落 {len(b.body)} / 图片 {len(b.images)} / 脚注 {len(b.footnotes)}")
    print(f"大小 {OUT.stat().st_size / 1024:.0f} KB")


if __name__ == "__main__":
    main()
