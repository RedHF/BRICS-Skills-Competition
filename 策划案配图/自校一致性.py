# -*- coding: utf-8 -*-
"""自校：把正式稿中的关键数值与 chapters.json / 代码事实逐项比对。"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MD = ROOT / "《檐下千秋》游戏策划案（正式稿）.md"
J = json.loads((ROOT / "LLM-tmp/服务端/content/chapters.json").read_text(encoding="utf-8"))
md = MD.read_text(encoding="utf-8")

ok = fail = 0


def chk(desc, cond, detail=""):
    global ok, fail
    if cond:
        ok += 1
        print(f"  OK   {desc}")
    else:
        fail += 1
        print(f"  FAIL {desc}  {detail}")


print("=== 一、内容源事实 ===")
chk("内容协议 v10", J["version"] == 10 and "v10" in md)
chk("章节数 5", len(J["chapters"]) == 5 and "五章十任务" in md)
n_ev = sum(len(c["events"]) for c in J["chapters"])
chk("事件数 10", n_ev == 10, f"实际 {n_ev}")
chk("墨灵数 10", len(J["memories"]) == 10)
chk("技艺数 5", len(J["skills"]) == 5)

print("=== 二、技能数值 ===")
for name, dmg, sh, hl, cd in [("挥墨", 10, 0, 0, 500), ("斗拱", 0, 2, 0, 6000),
                              ("飞檐", 25, 0, 0, 4000), ("藻井", 18, 0, 1, 6000),
                              ("闪身", 0, 1, 0, 2500)]:
    s = J["skills"][name]
    chk(f"{name} 伤害{dmg}/护盾{sh}/净化{hl}/冷却{cd}",
        s["damage"] == dmg and s["shield"] == sh and s["heal"] == hl and s["cooldown_ms"] == cd)

print("=== 三、战斗配置（8 场，与正文表逐行比对） ===")
expect = {
    "prologue_bridge": (1, 640, None, ["斗拱"]),
    "temple_incense": (1, 680, None, ["斗拱"]),
    "temple_drum": (1, 740, None, ["藻井"]),
    "opera_opening": (2, 300, 620, ["斗拱", "藻井", "飞檐"]),
    "opera_master": (1, 1000, None, ["飞檐"]),
    "archway_form": (2, 520, None, ["飞檐"]),
    "archway_craftsman": (2, 540, None, ["斗拱", "飞檐"]),
    "tower_ascent": (3, 360, None, ["斗拱", "飞檐", "藻井"]),
}
found = {}
for c in J["chapters"]:
    for e in c["events"]:
        if "battle" in e:
            b = e["battle"]
            found[e["id"]] = (b["waves"], b["enemy_hp"], b.get("boss_hp"), b["required_skills"])
chk("战斗场次 8", len(found) == 8, f"实际 {len(found)}")
for k, v in expect.items():
    chk(f"{k} 波数{v[0]}/生命{v[1]}/首领{v[2]}/技艺{v[3]}", found.get(k) == v, f"实际 {found.get(k)}")
chk("开场锣首领名在正文", "白蚀·噤声客" in md)
chk("开场锣 620 生命在正文", "620" in md and "300" in md)

print("=== 四、容量与经济 ===")
inc = {e["id"]: e["reward"]["capacity_increase"] for c in J["chapters"] for e in c["events"]
       if e.get("reward", {}).get("capacity_increase")}
chk("扩容点为社鼓声与无名匠", inc == {"temple_drum": 1, "archway_craftsman": 1}, f"实际 {inc}")
chk("初始容量 5 / 上限 7 在正文", "初始 **5 道**" in md and "**7 道**" in md)
chk("章节解锁费用全 0", all(c["unlock_cost"] == 0 for c in J["chapters"]))
chk("正文写明章节解锁 0 墨痕", "**0 墨痕**" in md)

print("=== 五、结算公式 ===")
chk("权重 40/30/30 在正文", "R×40 + B×30 + M×30" in md)
chk("星级阈值 85/60 在正文", "Q ≥ 85" in md and "60 ≤ Q < 85" in md)
chk("错误扣分 min(20, ×5) 在正文", "min(20, 非描摹错误次数 × 5)" in md)
chk("侵蚀≥70 扣 15 在正文", "侵蚀 ≥ 70 ? 15 : 0" in md)

print("=== 六、侵蚀与描摹 ===")
chk("描摹失败 0 侵蚀在正文", "**0**（不惩罚练习）" in md)
chk("非描摹 +10 在正文", "**+10**" in md)
chk("tolerance 0.14 在正文", "0.14" in md)
chk("1.6 倍容差在正文", "1.6 倍" in md)
chk("跳距 0.12 在正文", "0.12" in md)

print("=== 七、叙事与配音 ===")
nd = sum(len(e["story"].get("dialogue", [])) for c in J["chapters"] for e in c["events"])
nc = sum(len(e["story"].get("clues", [])) for c in J["chapters"] for e in c["events"])
nb = sum(len(e["story"].get("beats", [])) for c in J["chapters"] for e in c["events"])
chk("开场对话 60 句", nd == 60, f"实际 {nd}")
chk("调查线索 30 条", nc == 30, f"实际 {nc}")
chk("往事独白 30 条", nb == 30, f"实际 {nb}")
voice = list((ROOT / "LLM-tmp/客户端/assets/voice").glob("*.wav"))
chk("配音 184 段", len(voice) == 184, f"实际 {len(voice)}")
chk("正文写明 184 段", "184" in md)
chk("失败演出 9 句", len(J["failure_scene"]["dialogue"]) == 9)
chk("失败首句 4 变体", len(J["failure_scene"]["first_lines"]) == 4)

print("=== 八、排版要素 ===")
for kw in ["墨灵", "白蚀", "心舍", "墨痕", "侵蚀度", "拓印", "檐下谱", "榫卯", "斗拱", "飞檐", "藻井"]:
    chk(f"关键词「{kw}」已在正文出现", kw in md)

print()
print(f"通过 {ok} 项，失败 {fail} 项")
