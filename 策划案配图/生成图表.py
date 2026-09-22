# -*- coding: utf-8 -*-
"""生成《檐下千秋》策划案可视化图表（UI 线框图 / 页面结构图 / 核心玩法流程图）。
纯 PIL 绘制，输出 PNG，供策划案正文与 docx 嵌入使用。"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parent
MSYH = r"C:\Windows\Fonts\msyh.ttc"
MSYHB = r"C:\Windows\Fonts\msyhbd.ttc"

INK = (26, 42, 40)
LINE = (61, 91, 81)
FILL = (242, 245, 244)
FILL2 = (226, 235, 232)
GOLD = (154, 137, 96)
GREY = (110, 125, 121)
WHITE = (255, 255, 255)
RED = (168, 70, 64)


def font(size, bold=False):
    return ImageFont.truetype(MSYHB if bold else MSYH, size)


def text(d, xy, s, size=20, bold=False, fill=INK, anchor="la"):
    d.text(xy, s, font=font(size, bold), fill=fill, anchor=anchor)


def box(d, x, y, w, h, fill=FILL, outline=LINE, width=2, r=8):
    d.rounded_rectangle([x, y, x + w, y + h], radius=r, fill=fill, outline=outline, width=width)


def label_box(d, x, y, w, h, s, size=20, bold=True, fill=FILL, outline=LINE, r=8, tcolor=INK):
    box(d, x, y, w, h, fill=fill, outline=outline, r=r)
    text(d, (x + w / 2, y + h / 2), s, size, bold, tcolor, anchor="mm")


def arrow(d, p1, p2, color=LINE, width=2, head=9):
    d.line([p1, p2], fill=color, width=width)
    import math
    ang = math.atan2(p2[1] - p1[1], p2[0] - p1[0])
    for s in (+1, -1):
        a = ang + s * math.radians(153)
        d.line([p2, (p2[0] + head * math.cos(a), p2[1] + head * math.sin(a))], fill=color, width=width)


# --------------------------------------------------------------------------
# 图 1：UI 线框图
# --------------------------------------------------------------------------
def wireframes():
    W, H = 1760, 1080
    img = Image.new("RGB", (W, H), WHITE)
    d = ImageDraw.Draw(img)
    text(d, (W / 2, 34), "《檐下千秋》UI 线框图（竖屏 540×960 逻辑分辨率）", 34, True, INK, "mm")

    pw, ph = 380, 860
    top = 110
    gap = 32
    x0 = (W - (pw * 4 + gap * 3)) / 2

    def frame(x, title):
        box(d, x, top, pw, ph, WHITE, LINE, 3, 10)
        d.rectangle([x, top, x + pw, top + 46], fill=FILL2, outline=LINE, width=0)
        text(d, (x + pw / 2, top + 23), title, 22, True, INK, "mm")
        return x + 12, top + 58, pw - 24, ph - 70

    def topbar(x, y, w):
        box(d, x, y, w, 74, FILL, LINE, 2, 6)
        text(d, (x + 12, y + 12), "檐 下 千 秋", 19, True)
        text(d, (x + w - 12, y + 12), "识海 3/5 · 墨痕 6", 15, False, INK, "ra")
        text(d, (x + 12, y + 40), "侵蚀 45/100 · 蚀", 15, False, GREY)
        d.rounded_rectangle([x + 12, y + 58, x + w - 12, y + 66], radius=4, fill=(220, 224, 222))
        d.rounded_rectangle([x + 12, y + 58, x + 12 + (w - 24) * 0.45, y + 66], radius=4, fill=(216, 182, 124))
        return y + 84

    def navbar(x, y, w):
        labels = ["地图", "心舍", "账册", "设置", "剧情"]
        bw = (w - 8 * 4) / 5
        for i, s in enumerate(labels):
            label_box(d, x + i * (bw + 8), y, bw, 44, s, 15, False, FILL2, LINE, 6)

    def wrap(s, n):
        return [s[i:i + n] for i in range(0, len(s), n)]

    # ① 古建地图
    x, y, w, h = frame(x0, "① 古建地图（主界面）")
    y = topbar(x, y, w)
    label_box(d, x, y, w, 40, "当前任务：社庙 · 檐下客", 16, True, FILL2, LINE, 6)
    y += 50
    for ch, evs, done in [("序章·风雨廊桥", ["桥上平安 · 已修复"], True),
                          ("第一章·社庙", ["香火断 · 已修复", "檐下客 （进行中）", "社鼓声"], False),
                          ("第二章·戏楼", ["完成上一章节后开放"], True)]:
        bh = 46 + 34 * len(evs)
        box(d, x, y, w, bh, WHITE, LINE, 2, 6)
        d.line([x, y, x, y + bh], fill=GOLD, width=4)
        text(d, (x + 12, y + 12), ch, 17, True)
        for i, e in enumerate(evs):
            c = GREY if done else INK
            text(d, (x + 20, y + 40 + i * 30), "· " + e, 15, False, c)
        y += bh + 10
    navbar(x, top + ph - 56, w)

    # ② 建筑调查
    x, y, w, h = frame(x0 + pw + gap, "② 建筑调查（2.5D 场景）")
    y = topbar(x, y, w)
    text(d, (x + 2, y), "社庙侧厢 · 檐下客", 17, True)
    y += 28
    box(d, x, y, w, 300, (222, 230, 227), LINE, 2, 6)
    text(d, (x + w / 2, y + 16), "斜视建筑场景（可移动）", 14, False, GREY, "ma")
    for cx, cy, c in [(0.30, 0.42, GOLD), (0.62, 0.30, GOLD), (0.50, 0.70, (120, 170, 130))]:
        px, py = x + w * cx, y + 30 + 250 * cy
        d.ellipse([px - 9, py - 9, px + 9, py + 9], fill=c, outline=WHITE, width=2)
    d.polygon([(x + 40, y + 250), (x + 62, y + 232), (x + 84, y + 250), (x + 84, y + 288), (x + 40, y + 288)],
              fill=(56, 74, 72))
    d.ellipse([x + 52, y + 216, x + 72, y + 236], fill=(56, 74, 72))
    text(d, (x + 8, y + 272), "WASD／摇杆移动", 13, False, WHITE)
    y += 312
    text(d, (x + 2, y), "调查进度 2/3", 16, True, (74, 140, 100))
    y += 26
    for s in ["✓ 门楣残字", "✓ 半碗冷饭", "○ 补过的蓑衣"]:
        text(d, (x + 8, y), s, 15, False, INK if s[0] == "○" else (74, 140, 100))
        y += 24
    y += 8
    box(d, x, y, w, 92, WHITE, LINE, 2, 6)
    text(d, (x + 10, y + 10), "线索文案（逐条解锁）", 14, False, GREY)
    for i, l in enumerate(wrap("门内残纸写着「心宁而后身安」。缺字的答案就在待客的心意里。", 21)):
        text(d, (x + 12, y + 32 + i * 22), l, 14)
    navbar(x, top + ph - 56, w)

    # ③ 守护战
    x, y, w, h = frame(x0 + (pw + gap) * 2, "③ 白蚀守护战")
    y = topbar(x, y, w)
    text(d, (x + 2, y), "首领战 · 白蚀·噤声客", 17, True, RED)
    y += 28
    box(d, x, y, w, 268, (232, 236, 235), LINE, 2, 6)
    box(d, x + 14, y + 14, w - 28, 14, (57, 68, 72), GREY, 1, 3)
    d.rounded_rectangle([x + 14, y + 14, x + 14 + (w - 28) * 0.55, y + 28], radius=3, fill=(230, 162, 117))
    text(d, (x + 18, y + 32), "白蚀·噤声客  341/620", 13, False, INK)
    d.ellipse([x + w / 2 - 34, y + 84, x + w / 2 + 34, y + 152], fill=(236, 238, 236), outline=(200, 172, 120), width=3)
    d.line([(x + w / 2, y + 152), (x + w / 2 - 30, y + 252)], fill=RED, width=2)
    text(d, (x + w / 2, y + 214), "白蚀锁定 · 保持移动即可闪身", 13, False, RED, "mm")
    d.polygon([(x + 60, y + 220), (x + 82, y + 202), (x + 104, y + 220), (x + 104, y + 258), (x + 60, y + 258)],
              fill=(56, 74, 72))
    d.ellipse([x + 72, y + 186, x + 92, y + 206], fill=(56, 74, 72))
    text(d, (x + 8, y + 242), "拓印师 · 护盾 2 · 受蚀 3", 13, False, WHITE)
    y += 280
    text(d, (x + 2, y), "第 2/2 波 · 剩余 28 秒 · 受蚀 3/12", 15, True)
    y += 26
    label_box(d, x, y, w, 46, "开始守护 · 准备好再迎战", 17, True, (240, 238, 230), GOLD, 6, (110, 96, 60))
    y += 56
    keys = ["1 挥墨", "2 斗拱", "3 藻井", "4 飞檐", "5 闪身"]
    bw, bh2 = (w - 8) / 2, 42
    for i, k in enumerate(keys):
        cx = x + (i % 2) * (bw + 8)
        cy = y + (i // 2) * (bh2 + 8)
        lab = lab2 = k
        if i == 2:
            lab2 = k + " · 3.4 秒"
        label_box(d, cx, cy, bw, bh2, lab2, 14, False, FILL, LINE, 6)
    navbar(x, top + ph - 56, w)

    # ④ 事件结算
    x, y, w, h = frame(x0 + (pw + gap) * 3, "④ 事件结算")
    y = topbar(x, y, w)
    text(d, (x + w / 2, y + 6), "古建修复 · ★ ★ ★", 24, True, GOLD, "ma")
    y += 42
    box(d, x + 60, y, w - 120, 150, (238, 235, 226), LINE, 2, 6)
    text(d, (x + w / 2, y + 75), "拓印收藏图", 15, False, GREY, "mm")
    y += 162
    for i, l in enumerate(wrap("你把「宁安」收入檐下谱。门楣重新挂上那块缺了字的匾，侧厢的门没有关。", 20)):
        text(d, (x + 12, y + i * 24), l, 15)
    y += 24 * len(wrap("你把「宁安」收入檐下谱。门楣重新挂上那块缺了字的匾，侧厢的门没有关。", 20)) + 10
    for s in ["修复度 100%   白蚀清除度 无战斗", "记忆保留度 60%   综合评分 88/100", "获得墨痕 3"]:
        text(d, (x + 12, y), s, 15, False, INK)
        y += 24
    y += 10
    box(d, x, y, w, 62, FILL2, LINE, 2, 6)
    text(d, (x + 12, y + 10), "你交给人间的回答：留白让后来人续写", 14, False, INK)
    text(d, (x + 12, y + 34), "首次通关 · 追加一句通关呓语", 13, False, GREY)
    y += 70
    label_box(d, x, y, w, 44, "继续古建旅程", 17, True, FILL, LINE, 6)
    navbar(x, top + ph - 56, w)

    img.save(OUT / "图表-UI线框图.png")
    print("saved 图表-UI线框图.png")


# --------------------------------------------------------------------------
# 图 2：页面结构图
# --------------------------------------------------------------------------
def sitemap():
    W, H = 1760, 1100
    img = Image.new("RGB", (W, H), WHITE)
    d = ImageDraw.Draw(img)
    text(d, (W / 2, 34), "《檐下千秋》页面结构图", 34, True, INK, "mm")
    text(d, (W / 2, 76), "底部五个常驻入口：地图 / 心舍 / 账册 / 设置 / 剧情", 19, False, GREY, "mm")

    bw, bh = 168, 58
    nodes = {}

    def nd(key, x, y, s, fill=FILL, obs=False):
        label_box(d, x, y, bw, bh, s, 17, True, fill, LINE if not obs else GOLD, 8)
        nodes[key] = (x + bw / 2, y + bh / 2, x, y)

    def link(a, b, lab="", dash=False, color=LINE):
        ax, ay, _, _ = nodes[a]
        bx, by, _, _ = nodes[b]
        if dash:
            import math
            steps = 26
            for i in range(steps):
                if i % 2:
                    continue
                t1, t2 = i / steps, (i + 1) / steps
                d.line([(ax + (bx - ax) * t1, ay + (by - ay) * t1),
                        (ax + (bx - ax) * t2, ay + (by - ay) * t2)], fill=color, width=2)
        else:
            arrow(d, (ax, ay), (bx, by), color)
        if lab:
            mx, my = (ax + bx) / 2, (ay + by) / 2
            d.rectangle([mx - len(lab) * 7 - 4, my - 13, mx + len(lab) * 7 + 4, my + 13], fill=WHITE)
            text(d, (mx, my), lab, 14, False, GREY, "mm")

    # 主流程（纵向）
    nd("splash", W / 2 - bw / 2, 120, "开屏", FILL2)
    nd("map", W / 2 - bw / 2, 230, "古建地图", (240, 238, 228))
    nd("dialogue", W / 2 - bw / 2, 340, "开场对话", FILL2)
    nd("intro", W / 2 - bw / 2, 450, "建筑调查", FILL2)
    nd("puzzle", W / 2 - bw / 2, 560, "修复谜题", FILL2)
    nd("choice", W / 2 - bw / 2, 670, "墨灵抉择", FILL2)
    nd("battle", W / 2 - bw / 2, 780, "白蚀守护战", FILL2)
    nd("settlement", W / 2 - bw / 2, 890, "事件结算", (240, 238, 228))

    link("splash", "map", "连接并建档")
    link("map", "dialogue", "点任务卡")
    link("dialogue", "intro", "读完／跳过")
    link("intro", "puzzle", "三处调查完成")
    link("puzzle", "choice", "全部步骤通过")
    link("choice", "battle", "8/10 任务")
    link("battle", "settlement", "结算战果")
    d.line([(nodes["choice"][0], nodes["choice"][1] + bh / 2), (nodes["choice"][0] - 300, nodes["choice"][1] + bh / 2)],
           fill=LINE, width=2)
    d.line([(nodes["choice"][0] - 300, nodes["choice"][1] + bh / 2), (nodes["choice"][0] - 300, nodes["settlement"][1])],
           fill=LINE, width=2)
    arrow(d, (nodes["choice"][0] - 300, nodes["settlement"][1]), (nodes["settlement"][0] - bw / 2, nodes["settlement"][1]))
    text(d, (nodes["choice"][0] - 292, (nodes["choice"][1] + nodes["settlement"][1]) / 2), "檐下客／千层墨无战斗", 14, False, GREY)
    arrow(d, (nodes["settlement"][0] - bw / 2, nodes["settlement"][1]), (nodes["map"][0] - bw / 2, nodes["map"][1]))
    text(d, (nodes["map"][0] - 210, (nodes["map"][1] + nodes["settlement"][1]) / 2), "继续古建旅程", 14, False, GREY)

    # 失败支线（右侧）
    nd("gameover", W / 2 + 430, 560, "失败演出·飞鸟山", (240, 230, 228), True)
    nd("failed", W / 2 + 430, 670, "回溯 / 返回地图", (240, 230, 228), True)
    link("puzzle", "gameover", "判定失败", True, RED)
    link("gameover", "failed", "读满九句", True, RED)
    d.line([(nodes["failed"][0], nodes["failed"][1] - bh / 2), (nodes["failed"][0], nodes["failed"][1] - bh / 2 - 40)],
           fill=RED, width=2)
    d.line([(nodes["failed"][0], nodes["failed"][1] - bh / 2 - 40), (nodes["intro"][0] + bw / 2, nodes["failed"][1] - bh / 2 - 40)],
           fill=RED, width=2)
    arrow(d, (nodes["intro"][0] + bw / 2, nodes["failed"][1] - bh / 2 - 40),
          (nodes["intro"][0] + bw / 2, nodes["intro"][1] + bh / 2), RED)
    text(d, ((nodes["failed"][0] + nodes["intro"][0]) / 2, nodes["failed"][1] - bh / 2 - 34), "消耗 1 墨痕回溯（墨痕为 0 时免费）",
         14, False, RED, "ma")

    # 常驻入口（左侧）
    lx = 70
    entries = [("memories", "心舍", 300), ("ledger", "记忆账册", 420),
               ("journal", "檐下谱·剧情", 540), ("settings", "设置", 660)]
    for key, s, yy in entries:
        nd(key, lx, yy, s, FILL2)
        d.line([(lx + bw, yy + bh / 2), (nodes["map"][0] - bw / 2 - 30, yy + bh / 2)], fill=LINE, width=2)
        d.line([(nodes["map"][0] - bw / 2 - 30, yy + bh / 2), (nodes["map"][0] - bw / 2 - 30, nodes["map"][1] + 40)],
               fill=LINE, width=2)
        arrow(d, (nodes["map"][0] - bw / 2 - 30, nodes["map"][1] + 40), (nodes["map"][0] - bw / 2, nodes["map"][1] + 40), LINE)
    text(d, (lx + bw / 2, 250), "常驻导航（事件进行中可随时打开，暂停当前进度）", 15, True, GREY, "ma")

    # 心舍子页
    nd("memory", lx + 250, 300, "墨灵详情", FILL2)
    nd("compare", lx + 250, 660, "墨灵对照", FILL2)
    link("memories", "memory", "点卡片")
    d.line([(nodes["choice"][0] - bw / 2, nodes["choice"][1]), (lx + 250 + bw / 2, nodes["choice"][1])], fill=LINE, width=2)
    arrow(d, (lx + 250 + bw / 2, nodes["choice"][1]), (lx + 250 + bw / 2, nodes["compare"][1] + bh / 2))
    text(d, (lx + 250 + bw / 2 + 8, (nodes["choice"][1] + nodes["compare"][1]) / 2 + 6), "并排对比", 14, False, GREY)

    # 对话演出说明
    box(d, W - 520, 120, 440, 108, (248, 248, 246), GOLD, 2, 8)
    text(d, (W - 500, 138), "说明", 19, True, GOLD)
    text(d, (W - 500, 168), "· 对话演出为全屏模态层，期间屏蔽底部导航", 15)
    text(d, (W - 500, 192), "· 心舍 / 账册 / 剧情 / 设置可从事件中途打开", 15)

    img.save(OUT / "图表-页面结构图.png")
    print("saved 图表-页面结构图.png")


# --------------------------------------------------------------------------
# 图 3：核心玩法流程图
# --------------------------------------------------------------------------
def flowchart():
    W, H = 1360, 1500
    img = Image.new("RGB", (W, H), WHITE)
    d = ImageDraw.Draw(img)
    text(d, (W / 2, 34), "《檐下千秋》核心玩法流程图", 34, True, INK, "mm")

    bw, bh = 300, 66
    cx = 640

    def nd(y, s, sub="", fill=FILL, outline=LINE, w=bw):
        label_box(d, cx - w / 2, y, w, bh, s, 20, True, fill, outline, 9)
        if sub:
            text(d, (cx, y + bh + 16), sub, 15, False, GREY, "mm")
        return y

    def vl(y1, y2, lab=""):
        arrow(d, (cx, y1 + bh), (cx, y2), LINE)
        if lab:
            d.rectangle([cx - len(lab) * 7 - 6, (y1 + bh + y2) / 2 - 13, cx + len(lab) * 7 + 6, (y1 + bh + y2) / 2 + 13],
                        fill=WHITE)
            text(d, (cx, (y1 + bh + y2) / 2), lab, 15, False, GREY, "mm")

    steps = [
        ("古建地图：选择当前任务", "按剧情顺序解锁；已完成标记「已修复」"),
        ("开场对话：6 句具名演出", "古建与往事之声交替发言；可上一句／跳过／返回"),
        ("建筑调查：三处线索", "2.5D 场景移动；每处解锁一条线索与配音"),
        ("修复谜题：1–5 步", "描摹／构件归位／图式辨认／技艺机关"),
        ("墨灵显影与取舍", "容量不足时必须放下一段旧记忆（二次确认）"),
        ("白蚀守护战（8/10 任务）", "60 秒内清完全部波次，并施展任务要求的技艺"),
        ("结算：三星评定", "修复度 40% ＋ 白蚀清除度 30% ＋ 记忆保留度 30%"),
    ]
    y = 100
    ys = []
    for s, sub in steps:
        ys.append(y)
        nd(y, s, sub)
        y += bh + 62

    for i in range(len(steps) - 1):
        vl(ys[i], ys[i + 1])

    # 循环回边
    last = ys[-1]
    d.line([(cx + bw / 2, last + bh / 2), (cx + bw / 2 + 190, last + bh / 2)], fill=LINE, width=2)
    d.line([(cx + bw / 2 + 190, last + bh / 2), (cx + bw / 2 + 190, ys[0] + bh / 2)], fill=LINE, width=2)
    arrow(d, (cx + bw / 2 + 190, ys[0] + bh / 2), (cx + bw / 2, ys[0] + bh / 2), LINE)
    text(d, (cx + bw / 2 + 200, (ys[0] + last) / 2), "继续下一任务", 17, True, LINE, "ma")

    # 失败支线
    fy = ys[3] + bh + 34
    label_box(d, cx - bw / 2 - 470, fy, 300, bh, "失败演出 · 飞鸟山（九句）", 18, True, (246, 236, 234), RED, 9)
    arrow(d, (cx - bw / 2, ys[3] + bh / 2), (cx - bw / 2 - 170, ys[3] + bh / 2), RED)
    d.line([(cx - bw / 2 - 170, ys[3] + bh / 2), (cx - bw / 2 - 170, fy + bh / 2)], fill=RED, width=2)
    arrow(d, (cx - bw / 2 - 170, fy + bh / 2), (cx - bw / 2 - 170, fy + bh / 2), RED)
    text(d, (cx - bw / 2 - 180, ys[3] + bh / 2 - 14), "侵蚀 100／尝试用尽", 15, False, RED, "ra")

    label_box(d, cx - bw / 2 - 470, fy + bh + 40, 300, 54, "回溯：消耗 1 墨痕（0 时免费）", 16, False, (246, 236, 234), RED, 9)
    arrow(d, (cx - bw / 2 - 320, fy + bh), (cx - bw / 2 - 320, fy + bh + 40), RED)
    d.line([(cx - bw / 2 - 320, fy + bh + 94), (cx - bw / 2 - 320, ys[2] + bh / 2)], fill=RED, width=2)
    arrow(d, (cx - bw / 2 - 320, ys[2] + bh / 2), (cx - bw / 2, ys[2] + bh / 2), RED)
    text(d, (cx - bw / 2 - 330, ys[2] + bh / 2 - 14), "回到事件起点", 15, False, RED, "ra")

    box(d, 1130, 100, 210, 150, (248, 248, 246), GOLD, 2, 8)
    text(d, (1146, 116), "图例", 19, True, GOLD)
    text(d, (1146, 146), "流程主链", 15)
    text(d, (1146, 172), "失败与回溯", 15, False, RED)
    text(d, (1146, 198), "循环回边", 15)
    d.line([(1146, 230), (1330, 230)], fill=GOLD, width=4)

    img.save(OUT / "图表-核心玩法流程图.png")
    print("saved 图表-核心玩法流程图.png")


if __name__ == "__main__":
    wireframes()
    sitemap()
    flowchart()
