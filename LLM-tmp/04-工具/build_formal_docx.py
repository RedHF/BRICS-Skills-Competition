# -*- coding: utf-8 -*-
"""
生成《檐下千秋》游戏策划案 · 正式文案（临时稿）docx
按 BRICS2026 赛题 Task01 文档排版要求：
- 封面：作品名称 / 队伍 ID / 日期
- 标题：黑体三号（16pt）加粗
- 正文：宋体小四（12pt）、1.5 倍行距
- 关键词：蓝色高亮 + 脚注解释
- 页边距：2.54cm（1440 twips）
纯标准库实现（zipfile + 手写 OOXML）。
"""
import zipfile
from xml.sax.saxutils import escape

OUT = r"C:\Users\21178\Desktop\files\BRICS-Skills-Competition\《檐下千秋》游戏策划案（正式文案·临时稿）.docx"

# ---------------------------------------------------------------------------
# 关键词 -> 脚注解释（首次出现加脚注；所有出现均蓝色高亮）
# ---------------------------------------------------------------------------
KEYWORDS = {
    "墨灵": "由古建承载的「匠魂之忆」（情感、秘闻、失传技艺等）凝结而成的记忆灵质，肉眼不可见，是世界观中的核心概念。",
    "白蚀": "由「遗忘」逆结晶而成的侵蚀现象，被侵蚀的古建会褪色失忆；它是「被遗忘」的具象化，对抗白蚀即对抗遗忘。",
    "心舍": "主角承载墨灵符诏的背包系统，即「识海」；容量初始 5 道、上限 7 道墨灵，拓印新记忆需抹去旧记忆。",
    "墨痕": "游戏内唯一的进度资源，无传统货币；按事件星级（1–3 星）发放，用于回溯重试与章节解锁。",
    "侵蚀度": "替代生命值的失败风险条（0–100），解密失败 +10、战斗失败 +15、受伤 +5，达 100 时事件失败并进入「残迹」状态。",
    "拓印": "本作核心操作机制，跟随或重现墨线轨迹，将古建记忆复写为墨灵符诏；兼具解密工具与战斗技能双重用途。",
    "记忆账册": "章节界面展示玩家「记住/遗忘」抉择清单的叙事档案，随抉择分岔，并于终章回收呼应。",
    "建筑意": "世界观核心设定：墨痕王朝依赖建筑承载的「意」维系文明，分为技艺之忆（构件）、仪礼之忆（仪式区）、情感之忆（器物）三级结构。",
    "墨竭之劫": "墨痕王朝遭遇的文明危机：白蚀蔓延、古建褪色失忆、人民遗忘来历的总称。",
    "无我识海": "主角因失忆而具备的空白识海，是承载他人记忆的资格条件；空白《檐下谱》与空白识海互为表里。",
    "墨灵符诏": "拓印所得的记忆载体，兼具解密工具与战斗技能双重用途（斗拱=承重/防御，飞檐=穿透/远程，藻井=净化/治疗）。",
    "残迹": "事件失败后场景进入的永久失忆状态：该古建的这段记忆永久消散，剧情分支改变，无法再访原貌。",
    "榫卯": "中国传统木构建筑的接合方式，本作构件归位谜题的文化原型（如燕尾榫、斗与拱）。",
    "通天塔": "皇城中的七层高塔，终局场景；白蚀源头与「七天七夜营建」传说呼应，与识海上限 7 形成回环。",
}

# ---------------------------------------------------------------------------
# OOXML 工具函数
# ---------------------------------------------------------------------------
def esc(t):
    return escape(t, {'"': '&quot;'})

class Builder:
    def __init__(self):
        self.body = []
        self.footnotes = []          # 按序存放脚注文本
        self.footnote_id_of = {}     # 关键词 -> 脚注 id

    # ---- 运行（run） ----
    def run(self, text, font="宋体", size=24, bold=False, color=None, footnote=None):
        rpr = []
        if font:
            rpr.append(f'<w:rFonts w:ascii="{font}" w:eastAsia="{font}" w:hAnsi="{font}"/>')
        if bold:
            rpr.append("<w:b/>")
        if color:
            rpr.append(f'<w:color w:val="{color}"/>')
        rpr.append(f'<w:sz w:val="{size}"/><w:szCs w:val="{size}"/>')
        r = f'<w:r><w:rPr>{"".join(rpr)}</w:rPr><w:t xml:space="preserve">{esc(text)}</w:t></w:r>'
        if footnote is not None:
            r += f'<w:r><w:rPr><w:rStyle w:val="FootnoteReference"/></w:rPr><w:footnoteReference w:id="{footnote}"/></w:r>'
        return r

    def footnote_ref(self, fid):
        return f'<w:r><w:rPr><w:rStyle w:val="FootnoteReference"/></w:rPr><w:footnoteReference w:id="{fid}"/></w:r>'

    # ---- 段落 ----
    def para(self, runs, ppr=""):
        return f"<w:p>{ppr}{''.join(runs) if isinstance(runs, list) else runs}</w:p>"

    def body_para(self, text, first_line=True, align=None, bold=False):
        """正文：宋体小四、1.5 倍行距；可选首行缩进 2 字符、居中、加粗。"""
        ppr = '<w:pPr>'
        ppr += '<w:spacing w:line="360" w:lineRule="auto"/>'
        if first_line:
            ppr += '<w:ind w:firstLineChars="200" w:firstLine="480"/>'
        if align:
            ppr += f'<w:jc w:val="{align}"/>'
        ppr += '</w:pPr>'
        runs = self.render_text(text, bold=bold)
        return self.para(runs, ppr)

    def heading(self, text, level=1):
        """标题：黑体三号（32 半磅=16pt）加粗。level 1 居中，level 2 左对齐。"""
        sz = 32 if level == 1 else 28
        ppr = '<w:pPr>'
        ppr += '<w:spacing w:line="360" w:lineRule="auto" w:before="240" w:after="120"/>'
        if level == 1:
            ppr += '<w:jc w:val="center"/>'
        ppr += f'<w:outlineLvl w:val="{level-1}"/>'
        ppr += '</w:pPr>'
        runs = [self.run(text, font="黑体", size=sz, bold=True)]
        return self.para(runs, ppr)

    # ---- 文本渲染：处理 {{关键词}} 标记 ----
    def render_text(self, text, bold=False):
        runs = []
        buf = ""
        i = 0
        while i < len(text):
            if text.startswith("{{", i):
                end = text.find("}}", i + 2)
                if end == -1:
                    buf += text[i:]
                    break
                kw = text[i + 2:end]
                if buf:
                    runs.append(self.run(buf, bold=bold))
                    buf = ""
                fid = None
                if kw in KEYWORDS:
                    if kw not in self.footnote_id_of:
                        fid = len(self.footnotes) + 1
                        self.footnote_id_of[kw] = fid
                        self.footnotes.append(KEYWORDS[kw])
                    else:
                        fid = self.footnote_id_of[kw]
                runs.append(self.run(kw, bold=bold, color="0000FF", footnote=fid))
                i = end + 2
            else:
                buf += text[i]
                i += 1
        if buf:
            runs.append(self.run(buf, bold=bold))
        return runs

    # ---- 表格 ----
    def table(self, header, rows, widths=None):
        ncols = len(header)
        if widths is None:
            widths = [1] * ncols
        total = sum(widths)
        grid = "".join(f'<w:gridCol w:w="{int(9000 * w / total)}"/>' for w in widths)
        tblpr = (
            '<w:tblPr>'
            '<w:tblStyle w:val="TableGrid"/>'
            '<w:tblW w:w="0" w:type="auto"/>'
            '<w:tblBorders>'
            '<w:top w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
            '<w:left w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
            '<w:bottom w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
            '<w:right w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
            '<w:insideH w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
            '<w:insideV w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
            '</w:tblBorders>'
            '<w:tblLayout w:type="autofit"/>'
            '</w:tblPr>'
        )
        def cell(content, bold=False):
            ppr = '<w:pPr><w:spacing w:line="300" w:lineRule="auto"/></w:pPr>'
            runs = [self.run(content, font="宋体", size=21, bold=bold)]
            return f'<w:tc><w:tcPr><w:tcW w:w="0" w:type="auto"/></w:tcPr>{self.para(runs, ppr)}</w:tc>'
        rows_xml = []
        rows_xml.append("<w:tr>" + "".join(cell(h, bold=True) for h in header) + "</w:tr>")
        for row in rows:
            rows_xml.append("<w:tr>" + "".join(cell(c) for c in row) + "</w:tr>")
        return f'<w:tbl>{tblpr}<w:tblGrid>{grid}</w:tblGrid>{"".join(rows_xml)}</w:tbl>'

    def page_break(self):
        self.body.append(
            '<w:p><w:r><w:br w:type="page"/></w:r></w:p>'
        )

    def spacer(self, n=1):
        for _ in range(n):
            self.body.append('<w:p/>')

# ---------------------------------------------------------------------------
# 内容组装
# ---------------------------------------------------------------------------
b = Builder()

# ===== 封面 =====
b.spacer(4)
b.body.append(
    '<w:p><w:pPr><w:jc w:val="center"/><w:spacing w:line="360" w:lineRule="auto"/></w:pPr>'
    '<w:r><w:rPr><w:rFonts w:ascii="黑体" w:eastAsia="黑体" w:hAnsi="黑体"/>'
    '<w:sz w:val="44"/><w:szCs w:val="44"/></w:rPr>'
    '<w:t>《檐下千秋》游戏策划案</w:t></w:r></w:p>'
)
b.body.append(
    '<w:p><w:pPr><w:jc w:val="center"/><w:spacing w:line="360" w:lineRule="auto"/></w:pPr>'
    '<w:r><w:rPr><w:rFonts w:ascii="黑体" w:eastAsia="黑体" w:hAnsi="黑体"/>'
    '<w:sz w:val="28"/><w:szCs w:val="28"/></w:rPr>'
    '<w:t>（正式文案 · 临时稿）</w:t></w:r></w:p>'
)
b.spacer(3)
cover_lines = [
    ("作品名称：《檐下千秋》", "宋体", 28),
    ("队伍 ID：【待确认】", "宋体", 28),
    ("组别：【待确认】", "宋体", 28),
    ("日期：2026 年 8 月", "宋体", 28),
]
for txt, font, sz in cover_lines:
    b.body.append(
        f'<w:p><w:pPr><w:jc w:val="center"/><w:spacing w:line="480" w:lineRule="auto"/></w:pPr>'
        f'<w:r><w:rPr><w:rFonts w:ascii="{font}" w:eastAsia="{font}" w:hAnsi="{font}"/>'
        f'<w:sz w:val="{sz}"/><w:szCs w:val="{sz}"/></w:rPr>'
        f'<w:t>{esc(txt)}</w:t></w:r></w:p>'
    )
b.spacer(3)
b.body.append(b.body_para("依据《2026 一带一路暨金砖国家技能发展与技术创新大赛·首届 AI 赋能数字创意设计与应用赛项》赛道一（交互赛道·小游戏开发方向）Task01 要求编制。", first_line=False, align="center"))
b.page_break()

# ===== 前言 =====
b.body.append(b.heading("前言", 1))
b.body.append(b.body_para("本策划案为小游戏《檐下千秋》的正式游戏策划文档，围绕赛题主题「文化传承与数字再造」，从「建筑文化的空间叙事」维度切入。文档依据赛事评分标准，完整阐述游戏的概述与核心概念、核心玩法与机制、系统设计与世界观剧情、可视化表达、AI 赋能策划应用与协作记录，并附文档规范与提交自查清单，为后续美术资产设计（Task02）与核心交互实现（Task03）提供统一的策划基准。"))
b.body.append(b.body_para("本稿为正式文案临时稿：正文已按正式文档语言规范撰写，源稿中标注「待确认」的团队信息（队伍 ID、组别、账号归属、部分数值细节）以占位形式保留，待团队确认后填入终稿。"))

# ===== 一、游戏概述与核心概念 =====
b.body.append(b.heading("一、游戏概述与核心概念（对应评分点 1.1）", 1))

b.body.append(b.heading("1.1 游戏名称与核心概念", 2))
b.body.append(b.body_para("游戏名称定为《檐下千秋》，取意「檐下藏千秋，墨中定存亡」——中国古建的屋檐之下，承载着跨越千年的文明记忆。"))
b.body.append(b.body_para("核心概念：玩家扮演墨痕王朝最后的{{拓印}}师，以「{{拓印}}古建记忆」为战斗与抉择的核心能力，在「识海只能承载数道记忆」的伦理困境中对抗{{白蚀}}、拯救墨痕王朝。作品将「遗忘什么、记住什么」这一抽象命题，转化为可操作的玩法规则与可感知的世界观法则。"))

b.body.append(b.heading("1.2 游戏类型与定位", 2))
b.body.append(b.body_para("游戏类型定位为 2.5D 解密冒险 + 轻战斗。玩法重心为解密与叙事：{{拓印}}技能既是解密工具，也是战斗辅助；单场战斗时长控制在 30–60 秒，确保战斗不打断叙事节奏。"))
b.body.append(b.body_para("平台倾向为 PC（演示版本），同时预留移动端虚拟摇杆适配方案，兼顾赛事演示与后续商业化扩展。"))

b.body.append(b.heading("1.3 目标受众", 2))
b.body.append(b.body_para("目标受众为偏好国风叙事、策略解谜与轻度卡牌玩法的玩家，建议定位 16–35 岁年龄段。该群体对传统文化题材接受度高，对「抉择—代价」类机制敏感，与作品「记忆伦理」主题高度契合。"))

b.body.append(b.heading("1.4 视觉风格", 2))
b.body.append(b.body_para("视觉风格以国风水墨为基调，与「墨痕/墨灵」世界观相统一；参考官方波克 IP「灵画师」素材统一角色与场景风格（素材仅限参赛使用，使用记录存入 Task02/Original）。灵画师素材映射建议（待确认）：角色 3D 参考 ×3 对应拓印师主角立绘、匠魂拟人形象与关键事件角色；横屏尺寸参考对应主界面与调查场景构图基准。"))

b.body.append(b.heading("1.5 主题切入点与文化表达", 2))
b.body.append(b.body_para("主题切入采用赛题维度二「建筑文化的空间叙事」。取材中国传统建筑承载「记忆」的文化内涵，包括风雨廊桥、社庙、戏楼、牌坊、斗拱、飞檐、藻井、通天塔等典型建筑与构件。"))
b.body.append(b.body_para("设计理念遵循「保留 + 现代化转译」：完整保留{{榫卯}}、墨线{{拓印}}、藻井纹样等传统建筑语汇，并将其转译为游戏内的谜题机制与技能系统（详见第四、五章），使文化元素成为可交互的玩法本体，而非单纯的美术装饰。"))

b.body.append(b.heading("1.6 特色亮点（创新点）", 2))
b.body.append(b.body_para("本作相较同类作品的核心创新体现为以下五点："))
b.body.append(b.body_para("其一，解密驱动叙事：以古建构件的「{{拓印}}/修复谜题」推进剧情，{{榫卯}}归位、墨线{{拓印}}、文化知识谜题均承载叙事信息。"))
b.body.append(b.body_para("其二，背包即「{{心舍}}」：容量初始 5 道、上限 7 道{{墨灵}}；{{拓印}}新记忆必须亲手抹去一道旧记忆，抹除伴随视听代价（画面褪色、音效消失），将资源管理升维为伦理抉择。"))
b.body.append(b.body_para("其三，无传统 NPC：事件与剧情由「古建呓语」发布，营造孤寂苍凉的沉浸氛围，凸显建筑作为叙事主体的文化立场。"))
b.body.append(b.body_para("其四，轻战斗：{{拓印}}技能快速对抗{{白蚀}}（每场 30–60 秒），战斗服务于节奏而非数值堆叠。"))
b.body.append(b.body_para("其五，主题升维：从「对抗邪恶」升华为「记忆伦理」抉择——记住什么、遗忘什么由玩家决定，并在终局以{{记忆账册}}回收全部抉择。"))

b.body.append(b.heading("1.7 一句话宣传语", 2))
b.body.append(b.body_para("「檐下藏千秋，墨中定存亡。」", first_line=False, align="center"))

# ===== 二、核心玩法与机制设计 =====
b.body.append(b.heading("二、核心玩法与机制设计（对应评分点 1.2）", 1))

b.body.append(b.heading("2.1 核心循环", 2))
b.body.append(b.body_para("核心循环概括为：探索古建 → 聆听「呓语」接取事件 → 解密（{{拓印}}/构件修复谜题）→ 获得{{墨灵符诏}} → {{心舍}}容量抉择 → 轻量战斗对抗{{白蚀}} → 修复古建推进旅程。"))
b.body.append(b.body_para("玩家行为路径展开：从风雨廊桥醒来 → 游历社庙、戏楼、牌坊等古建 → 调查场景、聆听呓语 → 解谜（拼合斗拱、{{拓印}}墨线、识别构件）获得{{墨灵符诏}} → 为腾出识海空间不得不抹除旧记忆 → 以技能轻量对抗{{白蚀}}、修复古建、开启通路 → 走向皇城{{通天塔}}。"))

b.body.append(b.heading("2.2 操作机制", 2))
b.body.append(b.table(
    ["操作", "说明"],
    [
        ["2.5D 场景移动", "方向键 / 虚拟摇杆"],
        ["调查", "点击调查物体、聆听呓语"],
        ["解密交互", "拖拽构件归位、跟随墨线拓印"],
        ["心舍", "滑动浏览符诏 + 点击抉择（抹除需二次确认）"],
        ["战斗", "点击释放技能（斗拱 / 飞檐 / 藻井）"],
    ],
    widths=[2, 5],
))
b.spacer(1)

b.body.append(b.heading("2.3 核心规则（目标、胜负与结算）", 2))
b.body.append(b.body_para("识海（{{心舍}}）容量：初始 5 道{{墨灵}}，章节推进可扩充至上限 7 道。"))
b.body.append(b.body_para("{{拓印}}规则：获得新{{墨灵符诏}}时必须先择一旧记忆抹去（容量满时），抹除伴随视听与剧情代价。"))
b.body.append(b.body_para("胜负条件：解密成功或战斗获胜 → 修复古建、推进剧情；解密失败或战斗失败 → {{侵蚀度}}上升；{{侵蚀度}}达 100% → 事件失败。"))
b.body.append(b.body_para("结算方式：事件星级 1–3 星，由修复度、白蚀清除度、记忆保留度综合评定；无金币体系，进度资源为「{{墨痕}}」（用于解锁章节与回溯重试）。"))
b.body.append(b.body_para("{{记忆账册}}：章节界面展示「记住/遗忘」清单，形成玩家专属的叙事档案，于终章完成回收。"))

b.body.append(b.heading("2.4 失败与重试机制", 2))
b.body.append(b.body_para("本作不设生命值，改用{{侵蚀度}}（0–100）作为失败风险条：解密失败 +10，战斗失败 +15，战斗中受伤 +5/次。"))
b.body.append(b.body_para("{{侵蚀度}}达 100%：事件失败 → 该古建的这段记忆永久消散，场景进入「{{残迹}}」状态，剧情分支改变，无法再访原貌。"))
b.body.append(b.body_para("{{侵蚀度}}分三阶段（对应视觉反馈）：浸（0–40：建筑褪色、声音减弱）→ 蚀（40–70：构件崩解、呓语失真）→ 竭（70–100：进入「{{残迹}}」、记忆永久消散）。"))
b.body.append(b.body_para("重试机制：消耗 1 点「{{墨痕}}」回溯至事件起点；已{{拓印}}的记忆保留，降低挫败感。"))

b.body.append(b.heading("2.5 难度成长曲线", 2))
b.body.append(b.table(
    ["章节", "教学 / 机制", "解密复杂度", "白蚀强度"],
    [
        ["第一章 社庙", "教学（拓印、斗拱、藻井净化、心舍）", "单步拼合", "弱（1 波）"],
        ["第二章 戏楼", "引入抉择 + 飞檐远程", "多步谜题", "中（1–2 波）"],
        ["第三章 牌坊", "共鸣连携 + 条件谜题", "条件谜题", "较强（2 波）"],
        ["第四章 通天塔", "全机制 + 终极抉择", "综合谜题", "强（2–3 波）"],
    ],
    widths=[2, 3, 2, 2],
))
b.spacer(1)

b.body.append(b.heading("2.6 时长规划（对齐 Task03）", 2))
b.body.append(b.body_para("单事件（关卡）时长 5–8 分钟，以解密为主体；总量 4 章 × 每章 2–3 事件 ≈ 30–50 分钟。"))
b.body.append(b.body_para("Task03 演示范围：完整「社庙」章节（约 10 分钟），满足赛题「不少于 3 分钟可体验内容」要求并留有余量。"))

# ===== 三、系统设计与世界观剧情 =====
b.body.append(b.heading("三、系统设计与世界观剧情（对应评分点 1.3）", 1))

b.body.append(b.heading("3.1 角色系统", 2))
b.body.append(b.body_para("主角：墨痕王朝最后的「{{拓印}}师」，手持空白《檐下谱》（角色名待确认，可采用无名或玩家自定义设定）。"))
b.body.append(b.body_para("无传统 NPC：剧情通过「古建呓语」触发；角色形象灵感来自官方「灵画师」素材，以匠魂拟人化呈现。"))
b.body.append(b.body_para("成长体系：通过新{{墨灵符诏}}（技能）与{{心舍}}容量扩充实现成长，不设等级体系，成长完全由叙事驱动。"))

b.body.append(b.heading("3.2 经济与数值系统（初版数值表）", 2))
b.body.append(b.table(
    ["数值", "定义", "初版数值"],
    [
        ["识海容量", "心舍可承载墨灵数", "初始 5 → 社庙末 6 → 戏楼末 7（上限）。世界观理由：墨灵与承载者共鸣，承载越多自身记忆越被稀释——「记别人的事，忘自己的事」；上限 7 与「通天塔七层」传说呼应"],
        ["侵蚀度", "事件失败风险条", "0–100（浸 0–40 / 蚀 40–70 / 竭 70–100）；解密失败 +10 / 战斗失败 +15 / 受伤 +5；达 100 事件失败"],
        ["墨痕", "进度资源", "事件 1 星 = 1、2 星 = 2、3 星 = 3；回溯重试耗 1；章节解锁耗墨痕（待确认具体值）"],
        ["战斗时长", "单场轻战斗", "30–60 秒"],
    ],
    widths=[2, 3, 5],
))
b.spacer(1)
b.body.append(b.body_para("数值设计原则：无传统货币、无体力，避免惩罚性设计；「{{侵蚀度}}+{{残迹}}」取代失败挫败感，把失败转化为剧情分支体验。"))

b.body.append(b.heading("3.3 背包与道具系统（心舍）", 2))
b.body.append(b.body_para("背包即「{{心舍}}」：容量 5–7 道{{墨灵符诏}}，符诏 = 解密工具 + 战斗技能（双重用途）："))
b.body.append(b.body_para("斗拱 → 承重：解密（压机关 / 承重归位）；战斗（防御 / 护盾）。"))
b.body.append(b.body_para("飞檐 → 穿透：解密（远程触发 / 跨越）；战斗（远程攻击）。"))
b.body.append(b.body_para("藻井 → 净化：解密（清除污渍 / 显影墨线）；战斗（清除{{白蚀}} / 治疗）。"))
b.body.append(b.body_para("抹除旧记忆伴随视听代价（画面褪色、对应音效消失），并在{{记忆账册}}中记录。抹除的三重代价：① 视听——对应音效 / 色调消失；② 剧情——记忆回归或消散，影响分支与「{{残迹}}」；③ 系统——若被抹记忆为技能来源，技能仅做叙事性弱化（避免产生「最优解」压力，待确认）。"))

b.body.append(b.heading("3.4 世界观（时间 / 地点 / 背景）", 2))
b.body.append(b.body_para("时间：架空古风「墨痕王朝」。"))
b.body.append(b.body_para("地点：乡村社庙 → 城镇戏楼 → 皇城「{{通天塔}}」，沿途有风雨廊桥、牌坊等古建。"))
b.body.append(b.body_para("背景：墨痕王朝依靠「{{建筑意}}」维系文明——每座宫殿、亭台、廊桥都承载建造者的「匠魂之忆」（情感、秘闻、失传技艺），化作肉眼不可见的「{{墨灵}}」。王朝正遭「{{墨竭之劫}}」：{{白蚀}}蔓延，被侵蚀的古建褪色失忆、人民遗忘来历。唯一能对抗{{白蚀}}的是{{拓印}}下来的{{墨灵符诏}}，但识海有限——每{{拓印}}一道新记忆，就必须亲手抹去一道旧记忆。"))
b.body.append(b.body_para("{{白蚀}}成因链：遗忘 → {{墨灵}}失载（断墨）→ 逆结晶为{{白蚀}} → 侵蚀邻近建筑 → 更多记忆被抹除 → 循环加速（{{墨竭之劫}}）。{{白蚀}}不是外来敌人，而是「被遗忘」的具象化；对抗{{白蚀}}即对抗遗忘。"))
b.body.append(b.body_para("主角动机：从濒临崩塌的「风雨廊桥」醒来，沿古建脉络{{拓印}}记忆、对抗{{白蚀}}、探寻「{{墨竭之劫}}」真相。"))
b.body.append(b.body_para("{{拓印}}资格：主角失忆不是剧情漏洞，而是「{{无我识海}}」的资格条件——空白《檐下谱》与空白识海互为表里；普通人有记忆定见，无法承载他人记忆。"))

b.body.append(b.heading("3.5 剧情主线（四章结构与结局抉择）", 2))
b.body.append(b.table(
    ["章", "场景", "叙事核心", "机制引入", "关键抉择点"],
    [
        ["序章", "风雨廊桥", "醒来、获得《檐下谱》、学会拓印", "教学", "—"],
        ["一", "社庙", "香火记忆、修复主梁", "斗拱", "教学性小抉择"],
        ["二", "戏楼", "戏班绝响（地方戏记忆）", "飞檐", "为拓印「戏班绝响」，须抹去「童年社戏」记忆"],
        ["三", "牌坊", "「名」与「实」：功名、家族与无名匠人", "共鸣连携（藻井已在社庙获得）", "抹去无名匠人之忆以保全大匠之名？"],
        ["四", "通天塔", "白蚀源头 = 初代拓印师的「终极记忆」——他为建立永恒秩序抹去所有战乱与悲痛记忆并封存于塔；塔最终被遗忘、整体逆结晶，成为白蚀源头", "全机制", "终极抉择：将哪些记忆拓印回世界"],
    ],
    widths=[1, 2, 3, 2, 3],
))
b.spacer(1)
b.body.append(b.body_para("结局设计（建议 3 个，待确认）："))
b.body.append(b.body_para("「千秋尽墨」——{{拓印}}回所有记忆，世界恢复完整但重回伤痛；"))
b.body.append(b.body_para("「无垢之城」——保持遗忘，秩序永恒但世界苍白；"))
b.body.append(b.body_para("「檐下折中」——只记住值得记住的（由玩家在抉择中决定，达成隐藏条件）。"))

b.body.append(b.heading("3.6 世界观规则补全（场景 1 推演补丁）", 2))
b.body.append(b.body_para("本节内容源自 AI 推演「场景 1：世界观自洽」的产出（DeepSeek Harness，2026-08-28），完整留痕见 LLM-tmp/03-AI协作留痕/推演-场景1-世界观自洽/。补丁状态为「建议采纳 · 待团队确认」。"))
b.body.append(b.table(
    ["编号", "补丁", "要点", "已回写位置"],
    [
        ["P1", "建筑意三级结构", "技艺之忆→构件、仪礼之忆→仪式区、情感之忆→器物（调查点 = 记忆沉淀点）", "§3.4、第四章"],
        ["P2", "白蚀成因链", "遗忘→失载→逆结晶→侵蚀→循环；白蚀 = 「被遗忘」的具象化", "§3.4"],
        ["P3", "侵蚀三阶段", "浸 0–40 / 蚀 40–70 / 竭 70–100，对应视觉与机制", "§2.4、§3.2"],
        ["P4", "拓印资格", "主角失忆 = 「无我识海」资格，非漏洞", "§3.4"],
        ["P5", "识海容量理由", "「记别人的事，忘自己的事」共鸣稀释；上限 7 呼应通天塔七层", "§3.2"],
        ["P6", "抹除三重代价", "视听 + 剧情 + 技能（技能仅叙事性弱化，防最优解压力）", "§3.3"],
        ["P7", "终局统一", "终极记忆 + 通天塔整体遗忘，两说合一", "§3.5"],
    ],
    widths=[1, 3, 5, 2],
))
b.spacer(1)
b.body.append(b.body_para("同步提出的改进建议（4 条，待确认后并入对应章节）："))
b.body.append(b.body_para("① 将「遗忘」做成可感知的世界语言：章节间已修复建筑若不再探访，会在地图上缓慢褪色；"))
b.body.append(b.body_para("② 增设「残余回声」机制：被抹去的记忆偶尔碎片回闪（残影 / 音效），制造情感拉扯，为第四章账册回收埋线；"))
b.body.append(b.body_para("③ {{白蚀}}三阶段做成可交互视觉（浸 / 蚀 / 竭），服务评分点 1.4 与 Task03 演示；"))
b.body.append(b.body_para("④ 上限 7 与「{{通天塔}}七层、七天七夜营建」传说绑定，终局回环。"))

# ===== 四、解密谜题体系设计 =====
b.body.append(b.heading("四、解密谜题体系设计", 1))

b.body.append(b.heading("4.1 谜题类型清单", 2))
b.body.append(b.table(
    ["类型", "玩法描述", "文化表达点"],
    [
        ["A 墨线拓印", "跟随 / 重现墨线轨迹，在正确位置完成拓印", "传统拓印工艺"],
        ["B 构件归位（榫卯）", "拖拽斗拱 / 构件拼合归位，开启机关", "榫卯结构（燕尾榫、斗与拱）"],
        ["C 纹样识别", "识别藻井 / 檐角纹样、牌坊形制等级", "藻井图案、四柱三间等知识"],
        ["D 条件谜题", "多技能组合：斗拱压住 + 飞檐远程触发 + 藻井净化显影", "建筑构件协作意象"],
        ["E 抉择之问", "心舍容量抉择（情感机制，非逻辑谜题）", "记忆伦理主题"],
    ],
    widths=[3, 4, 3],
))
b.spacer(1)

b.body.append(b.heading("4.2 谜题与技能 / 古建对应表", 2))
b.body.append(b.table(
    ["章节", "主要谜题", "主要技能"],
    [
        ["社庙", "A 拓印 + B 单步归位", "斗拱（承重）"],
        ["戏楼", "B 多步 + C 纹样", "飞檐（穿透）"],
        ["牌坊", "C + D 条件谜题", "藻井（净化）+ 共鸣连携"],
        ["通天塔", "A–D 综合", "全技能"],
    ],
    widths=[2, 3, 3],
))
b.spacer(1)

b.body.append(b.heading("4.3 难度曲线", 2))
b.body.append(b.body_para("谜题难度按「单步拼合 → 多步谜题 → 条件谜题（双技能联动）→ 综合谜题（全技能 + 限时 / 限次条件）」逐级递进，与章节机制引入节奏同步。"))

b.body.append(b.heading("4.4 数值初版总表（汇总）", 2))
b.body.append(b.table(
    ["项", "值", "备注"],
    [
        ["心舍容量", "初始 5，上限 7", "章节末扩充"],
        ["侵蚀度", "0–100；+10 / +15 / +5", "达 100 事件失败（残迹）"],
        ["墨痕", "星级 1/2/3 → 1/2/3 点", "回溯耗 1；解锁章节耗墨痕（具体值待确认）"],
        ["战斗", "每场 30–60 秒，1–3 波", "波数随章节递增"],
        ["单事件", "5–8 分钟", "解密为主"],
        ["事件星级", "修复度 + 白蚀清除度 + 记忆保留度", "1–3 星"],
    ],
    widths=[2, 3, 3],
))
b.spacer(1)

# ===== 五、可视化表达 =====
b.body.append(b.heading("五、可视化表达（对应评分点 1.4）", 1))

b.body.append(b.heading("5.1 UI 线框图（文字版，≥3 张；成图可交 AI 生成草图后精修）", 2))
b.body.append(b.table(
    ["页面", "线框图内容描述"],
    [
        ["① 主界面《檐下谱》", "水墨古建背景；中央翻开的古卷轴《檐下谱》；顶部状态条（识海容量、墨痕数）；卷轴内入口：章节地图 / 记忆账册 / 心舍 / 设置"],
        ["② 2.5D 调查界面", "斜 45° 古建场景；角色可移动；可调查物体高亮描边；呓语以墨色波纹 + 气泡呈现；侵蚀度条常驻"],
        ["③ 解密界面", "构件 / 墨线谜题主画面；顶部谜题目标提示；错误操作给予「墨迹扩散」反馈（侵蚀度 +）；底部技能栏（斗拱 / 飞檐 / 藻井）"],
        ["④ 心舍界面", "5–7 个符诏格位横排；滑动浏览；选中查看墨灵详情（技能 + 来历）；「抹去」按钮需二次确认，确认时该符诏褪色 + 音效消失"],
        ["⑤ 抉择界面", "新旧两道记忆左右对比（图案 + 文字摘要）；代价预告（褪色 / 音效消失标注）；「拓印」与「保留」按钮"],
        ["⑥ 轻战斗界面", "复用 2.5D 场景；白蚀敌人 + 技能按钮；侵蚀度条；战斗 30–60 秒快速结算"],
        ["⑦ 事件结算界面", "星级展示；修复度 / 白蚀清除度 / 记忆保留度三项；墨痕奖励；「记忆账册」更新提示"],
    ],
    widths=[3, 7],
))
b.spacer(1)

b.body.append(b.heading("5.2 页面结构图（文字版跳转关系）", 2))
b.body.append(b.body_para("主界面《檐下谱》 → 古建地图 → 事件场景（调查 ⇄ 解密 ⇄ 战斗）→ 抉择界面 → 结算界面 → {{记忆账册}} / 地图。"))
b.body.append(b.body_para("{{心舍}}可从主界面与事件中随时打开（暂停性质）；设置从主界面进入。"))

b.body.append(b.heading("5.3 核心玩法流程图（文字版步骤）", 2))
b.body.append(b.body_para("进入古建 → 调查 / 聆听呓语（接取事件）→ 解密（{{拓印}} / 归位 / 纹样）→ 获得{{墨灵符诏}} → {{心舍}}抉择（保留 / 抹去）→ 轻战斗对抗{{白蚀}} → 修复古建 → 结算（星级 / {{墨痕}}）→ 推进地图 → 循环。"))

b.body.append(b.heading("5.4 其他图稿（可选加分）", 2))
b.body.append(b.body_para("墨痕王朝地图（社庙—戏楼—牌坊—{{通天塔}}）；{{拓印}}师立绘（灵画师风格）；{{白蚀}}侵蚀前后古建对比图（强调「褪色失忆」主题）。"))

# ===== 六、AI 赋能策划应用与协作记录 =====
b.body.append(b.heading("六、AI 赋能策划应用与协作记录（对应评分点 1.6）", 1))

b.body.append(b.heading("6.1 工具清单与分工（2026-08-28 已确认）", 2))
b.body.append(b.table(
    ["工具", "账号归属", "负责内容"],
    [
        ["DeepSeek Harness", "【账号待补】", "世界观 / 规则 / 数值 / 叙事脚本推演"],
        ["Codex", "【账号待补】", "技术验证与规则模拟"],
        ["截图", "—", "留痕辅证"],
    ],
    widths=[3, 3, 4],
))
b.spacer(1)
b.body.append(b.body_para("场景 1 推演已完成并留痕：LLM-tmp/03-AI协作留痕/推演-场景1-世界观自洽/。"))

b.body.append(b.heading("6.2 五个推演场景（每场景附可直接使用的提示词模板）", 2))
b.body.append(b.body_para("场景 1：世界观自洽——推演目标：补全「{{建筑意}}」体系（记忆如何承载、{{墨灵}}形成与消散、{{白蚀}}传播机制）。"))
b.body.append(b.body_para("提示词模板：我正在设计一款国风解密游戏《檐下千秋》，世界观如下：【粘贴背景故事】。请以世界观架构师身份，检查该设定的逻辑漏洞并补全规则：建筑如何承载记忆？墨灵如何形成与消散？白蚀如何传播？给出自洽性分析与 3 条改进建议。"))
b.body.append(b.body_para("场景 2：核心规则（{{心舍}}抉择）——推演目标：识海容量上限与「抹除记忆」的惩罚 / 补偿设计，如何不劝退玩家。"))
b.body.append(b.body_para("提示词模板：我的游戏核心机制是：识海容量有限（初始 5 上限 7），{{拓印}}新记忆必须抹去一道旧记忆，抹除有视听代价。请推演该机制的玩家体验风险（挫败感 / 选择瘫痪），并给出 2-3 版惩罚与补偿方案及推荐。"))
b.body.append(b.body_para("场景 3：技能平衡——推演目标：斗拱（防御）/ 飞檐（远程）/ 藻井（治疗）对{{白蚀}}敌人的克制关系与数值。"))
b.body.append(b.body_para("提示词模板：我设计了三技能双用途体系：斗拱 = 承重 / 防御，飞檐 = 穿透 / 远程攻击，藻井 = 净化 / 治疗。请设计白蚀敌人类型（1-3 波递增）与技能克制关系表，并给出战斗时长 30-60 秒内的数值建议。"))
b.body.append(b.body_para("场景 4：关卡结构——推演目标：四章节奏、叙事节点与记忆抉择点分布。"))
b.body.append(b.body_para("提示词模板：请为四章结构（社庙→戏楼→牌坊→{{通天塔}}）设计关卡节奏表：每章 2-3 个事件、谜题类型分配、叙事节点与记忆抉择点位置，确保每 5-8 分钟有一个情绪高点。"))
b.body.append(b.body_para("场景 5：解密谜题——推演目标：谜题类型与难度曲线适配 2.5D 场景。"))
b.body.append(b.body_para("提示词模板：请基于中国传统建筑元素（{{榫卯}}、斗拱、飞檐、藻井、墨线{{拓印}}）设计 10 个解密谜题，难度从单步到条件组合递增，并标注每个谜题的文化知识点。"))

b.body.append(b.heading("6.3 逐轮互动记录模板（做一轮填一行）", 2))
b.body.append(b.table(
    ["轮次", "日期", "工具", "本轮目标", "提示词原文（粘贴）", "AI 输出摘要", "人工修订了什么", "是否回流再迭代"],
    [
        ["1", "", "", "", "", "", "", ""],
        ["2", "", "", "", "", "", "", ""],
    ],
    widths=[1, 1, 1, 2, 2, 2, 2, 1],
))
b.spacer(1)

b.body.append(b.heading("6.4 留痕规范", 2))
b.body.append(b.body_para("留痕规范详见 LLM-tmp/03-AI协作留痕/AI协作记录留痕方案.md，采用 DSH /export、Codex codex export、截图 / 版本保留 / 来源标注等方式，支撑「可追溯、体现人机协同」的评分要求。"))
b.body.append(b.body_para("说明：官方 PDF 未明确「70% AI 占比」数字，但留痕越完整越安全；AI 输出与人工修订的对比记录本身即为得分点。"))

# ===== 七、文档规范与提交自查清单 =====
b.body.append(b.heading("七、文档规范与提交自查清单（对应评分点 1.5）", 1))
b.body.append(b.body_para("本策划案依照以下排版与提交规范编制，提交前逐项自查："))
b.body.append(b.body_para("☐ 封面：作品名称 + 队伍 ID + 日期；"))
b.body.append(b.body_para("☐ 标题黑体三号加粗；正文宋体小四、1.5 倍行距；页边距 2.54cm；"))
b.body.append(b.body_para("☐ 关键词蓝色高亮 + 脚注解释；"))
b.body.append(b.body_para("☐ 四个文件命名合规：Track01_Task01_<队伍ID后五位数字>_<作品名称>_游戏策划案.pdf/.docx 与 Track01_Task01_<队伍ID后五位数字>_<作品名称>_AI协作记录.pdf/.docx；"))
b.body.append(b.body_para("☐ 最终文件存 Task01/Final/；过程文件（本稿、提示词、截图）存 Task01/Original/。"))

# ===== 八、待确认事项汇总 =====
b.body.append(b.heading("八、待确认事项汇总", 1))
b.body.append(b.table(
    ["#", "事项", "建议默认值"],
    [
        ["1", "队伍 ID（后五位）、组别、提交日期、成员分工", "拿到后填入封面即可"],
        ["2", "AI 工具清单已确认（DSH + Codex + 截图）；账号归属待补", "填 §6.1 账号列即可"],
        ["3", "「70% AI 占比」说法", "官方 PDF 未见，以技术说明会 / QQ 群为准"],
        ["4", "心舍容量", "已统一：初始 5、上限 7"],
        ["5", "灵画师素材具体映射", "按 §1.4 建议，可留到 Task02 美术阶段定"],
        ["6", "结局数量", "建议 3 个（§3.5）"],
        ["7", "章节解锁消耗墨痕的具体值", "建议每章 2 墨痕"],
        ["8", "§3.6 场景 1 补丁 P1–P7 与 4 条改进建议", "团队审阅后逐条标「采纳 / 修改 / 否决」"],
    ],
    widths=[1, 6, 5],
))
b.spacer(1)
b.body.append(b.body_para("以上事项确认后，将替换正文中的「待确认」占位并定稿为终版策划案。", first_line=False, align="center"))

# ---------------------------------------------------------------------------
# 脚注 XML
# ---------------------------------------------------------------------------
def build_footnotes(footnotes):
    parts = [
        '<w:footnote w:type="separator" w:id="-1"><w:p><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr>'
        '<w:r><w:separator/></w:r></w:p></w:footnote>',
        '<w:footnote w:type="continuationSeparator" w:id="0"><w:p><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr>'
        '<w:r><w:continuationSeparator/></w:r></w:p></w:footnote>',
    ]
    for i, text in enumerate(footnotes, start=1):
        parts.append(
            f'<w:footnote w:id="{i}"><w:p><w:pPr><w:spacing w:line="240" w:lineRule="auto"/></w:pPr>'
            f'<w:r><w:rPr><w:rStyle w:val="FootnoteReference"/></w:rPr><w:footnoteRef/></w:r>'
            f'<w:r><w:rPr><w:rFonts w:ascii="宋体" w:eastAsia="宋体" w:hAnsi="宋体"/>'
            f'<w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr>'
            f'<w:t xml:space="preserve"> {esc(text)}</w:t></w:r></w:p></w:footnote>'
        )
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<w:footnotes xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        + "".join(parts)
        + '</w:footnotes>'
    )

# ---------------------------------------------------------------------------
# 打包 docx
# ---------------------------------------------------------------------------
def build_docx():
    document_xml = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<w:body>'
        + "".join(b.body)
        + '<w:sectPr>'
        '<w:pgSz w:w="11906" w:h="16838"/>'
        '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" '
        'w:header="851" w:footer="992" w:gutter="0"/>'
        '<w:cols w:space="425"/>'
        '<w:docGrid w:type="lines" w:linePitch="312"/>'
        '</w:sectPr>'
        '</w:body></w:document>'
    )

    styles_xml = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:docDefaults><w:rPrDefault><w:rPr>'
        '<w:rFonts w:ascii="宋体" w:eastAsia="宋体" w:hAnsi="宋体"/>'
        '<w:sz w:val="24"/><w:szCs w:val="24"/></w:rPr></w:rPrDefault>'
        '<w:pPrDefault><w:pPr><w:spacing w:line="360" w:lineRule="auto"/></w:pPr></w:pPrDefault>'
        '</w:docDefaults>'
        '<w:style w:type="paragraph" w:default="1" w:styleId="Normal">'
        '<w:name w:val="Normal"/><w:rPr><w:rFonts w:ascii="宋体" w:eastAsia="宋体" w:hAnsi="宋体"/>'
        '<w:sz w:val="24"/><w:szCs w:val="24"/></w:rPr></w:style>'
        '<w:style w:type="character" w:styleId="FootnoteReference">'
        '<w:name w:val="footnote reference"/><w:rPr><w:vertAlign w:val="superscript"/></w:rPr></w:style>'
        '<w:style w:type="table" w:styleId="TableGrid"><w:name w:val="Table Grid"/>'
        '<w:pPr><w:spacing w:line="300" w:lineRule="auto"/></w:pPr>'
        '<w:tblPr><w:tblBorders>'
        '<w:top w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
        '<w:left w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
        '<w:bottom w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
        '<w:right w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
        '<w:insideH w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
        '<w:insideV w:val="single" w:sz="4" w:space="0" w:color="auto"/>'
        '</w:tblBorders></w:tblPr></w:style>'
        '</w:styles>'
    )

    footnotes_xml = build_footnotes(b.footnotes)

    content_types = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
        '<Override PartName="/word/footnotes.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footnotes+xml"/>'
        '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
        '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>'
        '</Types>'
    )

    rels_root = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
        '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>'
        '</Relationships>'
    )

    doc_rels = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footnotes" Target="footnotes.xml"/>'
        '</Relationships>'
    )

    core_xml = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
        '<dc:title>《檐下千秋》游戏策划案（正式文案·临时稿）</dc:title>'
        '<dc:creator>BRICS AI 赋能数字创意设计与应用赛项参赛团队</dc:creator>'
        '<cp:lastModifiedBy>DeepSeek Harness</cp:lastModifiedBy>'
        '</cp:coreProperties>'
    )

    app_xml = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" '
        'xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">'
        '<Application>DeepSeek Harness</Application>'
        '</Properties>'
    )

    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", content_types)
        z.writestr("_rels/.rels", rels_root)
        z.writestr("word/document.xml", document_xml)
        z.writestr("word/_rels/document.xml.rels", doc_rels)
        z.writestr("word/styles.xml", styles_xml)
        z.writestr("word/footnotes.xml", footnotes_xml)
        z.writestr("docProps/core.xml", core_xml)
        z.writestr("docProps/app.xml", app_xml)

    print("SAVED:", OUT)
    print("FOOTNOTES:", len(b.footnotes))

if __name__ == "__main__":
    build_docx()
