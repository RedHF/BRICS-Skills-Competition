"""Lay out the six-page design and runtime supplement from verified assets."""
from pathlib import Path
import argparse
from datetime import date
import json
from xml.sax.saxutils import escape

from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.platypus import Paragraph, Table, TableStyle
from reportlab.pdfgen import canvas
from PIL import Image
import pypdfium2 as pdfium

ROOT = Path(__file__).resolve().parents[1]
CLIENT = ROOT / "LLM-tmp" / "客户端"
parser = argparse.ArgumentParser()
parser.add_argument("--revision",default="A11",choices=["A3","A6","A8","A9","A10","A11"])
args = parser.parse_args()
REV = args.revision
PREVIEW = {"A3":"A-preview3","A6":"A-preview6","A8":"A-preview8","A9":"A-preview9","A10":"A-preview10","A11":"A-preview11"}[REV]
OUTPUT = ROOT / "output" / "决赛修订材料" / ("回响版"+REV)
QA = ROOT / ".review" / ("echo-supplement-pdf" if REV == "A3" else "echo-supplement-pdf-"+REV.lower())
OUTPUT.mkdir(parents=True, exist_ok=True)
QA.mkdir(parents=True, exist_ok=True)

records = []
for path in (ROOT / "LLM-tmp" / "验证记录").glob("*-回响版/*exported-client/result.json"):
    value = json.loads(path.read_text(encoding="utf-8"))
    if value.get("passed") and value.get("visual") and value.get("full_journey") and not value.get("diagnostic_runtime_injection") and PREVIEW+"-" in value["archive"]:
        records.append((path, value))
evidence, verification = max(records, key=lambda pair: pair[0].stat().st_mtime)
demo_records = []
if REV != "A3":
    for path in (ROOT/"LLM-tmp"/"验证记录").glob("*-回响版/*exported-demos/result.json"):
        value = json.loads(path.read_text(encoding="utf-8"))
        if value.get("passed") and value.get("archive_sha256") == verification["archive_sha256"]:
            demo_records.append((path,value))
    demo_evidence, demos = max(demo_records,key=lambda pair:pair[0].stat().st_mtime)
SHOTS = evidence.parent / "frames"
for path in SHOTS.glob("*.png"):
    assert Image.open(path).size == (1920, 1080), path

pdfmetrics.registerFont(TTFont("SC", str(CLIENT / "assets/fonts/NotoSerifSC-Regular.ttf")))
FONT = "SC"
BLACK = colors.HexColor("#24211e")
MUTED = colors.HexColor("#736a5f")
PAPER = colors.HexColor("#f6f1e8")
RED = colors.HexColor("#a34838")
RULE = colors.HexColor("#d9d9d9")
W, H = 595.276, 841.89
LEFT, RIGHT = 46, 549.276
WIDTH = RIGHT-LEFT
FILE = OUTPUT / "檐下千秋_设计与运行修订说明.pdf"
c = canvas.Canvas(str(FILE), pagesize=(W,H), pageCompression=1)
c.setTitle("檐下千秋回响版设计与运行修订说明")
c.setAuthor("")
c.setCreator("")
c.setSubject(f"本科组 Track01 回响版 {REV} 设计修订与运行说明")

STYLES = {
    "body": ParagraphStyle("body",fontName=FONT,fontSize=10.5,leading=17,textColor=BLACK,wordWrap="CJK",spaceAfter=0),
    "small": ParagraphStyle("small",fontName=FONT,fontSize=8.5,leading=13.5,textColor=MUTED,wordWrap="CJK"),
    "cell": ParagraphStyle("cell",fontName=FONT,fontSize=9.2,leading=14,textColor=BLACK,wordWrap="CJK"),
    "head": ParagraphStyle("head",fontName=FONT,fontSize=10,leading=15,textColor=colors.white,wordWrap="CJK"),
}


def p(text, y, x=LEFT, width=WIDTH, style="body"):
    paragraph = Paragraph(escape(text).replace("\n","<br/>"),STYLES[style])
    _, height = paragraph.wrap(width,1000)
    assert y-height > 47, f"Text overflow: {text[:40]}"
    paragraph.drawOn(c,x,y-height)
    return y-height


def heading(text,y):
    c.setFillColor(BLACK)
    c.setFont(FONT,14)
    c.drawString(LEFT,y-14,text)
    return y-29


def start(number,title,subtitle):
    c.setFillColor(PAPER)
    c.rect(0,0,W,H,fill=1,stroke=0)
    c.setFillColor(RED)
    c.rect(LEFT,H-57,10,10,fill=1,stroke=0)
    c.setFont(FONT,8.5)
    c.setFillColor(MUTED)
    c.drawString(LEFT+17,H-56,"本科组 Track01")
    c.drawRightString(RIGHT,H-56,f"回响版 {REV}  "+date.today().strftime("%Y %m %d"))
    c.setFillColor(colors.black)
    c.setFont(FONT,21)
    c.drawString(LEFT,H-99,title)
    y = p(subtitle,H-115,style="small")-24
    c.setFont(FONT,8)
    c.setFillColor(MUTED)
    c.drawString(LEFT,29,"檐下千秋 设计与运行修订说明")
    c.drawRightString(RIGHT,29,f"{number} / 6")
    return y


def image(path,x,y,width,caption):
    iw,ih = Image.open(path).size
    height = width*ih/iw
    c.drawImage(str(path),x,y-height,width=width,height=height,mask="auto")
    p(caption,y-height-7,x,width,"small")
    return y-height-35


def table(headers,rows,widths,y):
    values = [[Paragraph(escape(t),STYLES["head"]) for t in headers]]
    values += [[Paragraph(escape(str(t)),STYLES["cell"]) for t in row] for row in rows]
    item = Table(values,colWidths=widths,hAlign="LEFT")
    item.setStyle(TableStyle([
        ("BACKGROUND",(0,0),(-1,0),colors.HexColor("#39342e")),
        ("ROWBACKGROUNDS",(0,1),(-1,-1),[colors.white,colors.HexColor("#eeeae2")]),
        ("GRID",(0,0),(-1,-1),.5,RULE),
        ("VALIGN",(0,0),(-1,-1),"MIDDLE"),
        ("LEFTPADDING",(0,0),(-1,-1),9),("RIGHTPADDING",(0,0),(-1,-1),9),
        ("TOPPADDING",(0,0),(-1,-1),8),("BOTTOMPADDING",(0,0),(-1,-1),8),
    ]))
    _,height = item.wrap(WIDTH,1000)
    assert y-height > 48,"Table overflow"
    item.drawOn(c,LEFT,y-height)
    return y-height-20


y = start(1,"檐下千秋回响版修订说明","把文化主题落实为可操作的修复、可比较的取舍与可回看的后果。")
y = p("《檐下千秋》是一款以古建与人的生活记忆为主题的叙事解谜作品。回响版延续原有五章结构，重点重做社庙章节，并统一心舍、技艺与记录的规则。玩家修复的是建筑承接生活的用途，也要决定哪些独特回应继续随身。",y)-18
y = image(SHOTS/"joinery-after.png",LEFT,y,WIDTH,"同一正殿中的修复结果 真实 Windows EXE 原生 1920×1080 引擎离屏渲染")
y = heading("从观察到后果",y)
labels = ["观察旧痕","修复用途","听见回声","做出取舍","回看后果"]
box_width = (WIDTH-48)/5
for i,label in enumerate(labels):
    x = LEFT+i*(box_width+12)
    c.setFillColor(colors.HexColor("#e6ddcc")); c.setStrokeColor(colors.HexColor("#b9aa8e"))
    c.roundRect(x,y-36,box_width,36,3,fill=1,stroke=1)
    c.setFont(FONT,10.5); c.setFillColor(BLACK); c.drawCentredString(x+box_width/2,y-23,label)
    if i<4:
        c.setStrokeColor(MUTED); c.line(x+box_width+2,y-18,x+box_width+10,y-18)
y -= 55
y = p("社庙不再主要依靠答字和连续战斗推进。结构判断、给来客留位、拓出既有鼓纹，分别对应共同营造、檐下待客与春社相聚。三次行动汇成第一次心舍满额取舍。",y)-16
y = p("当前范围为全局规则适配与社庙重点改版。其余章节保留既有玩法；后续设计不列为已实现成果。",y,style="small")
c.showPage()

y = start(2,"记录与鲜活共鸣分开","取舍承担叙事与感官上的失去，已经学会的手艺继续保留。")
y = table(["到达节点","心舍容量","展开条件"],[
    ["初始旅程","3 格","新旅程开始"],
    ["社庙章末 E04","4 格","完成修复、确认取舍并亲手敲鼓后结算"],
    ["牌坊章末 E08","5 格","完成该事件与选择后结算"],
],[115,75,WIDTH-190],y)
y = heading("三种合法处理方式",y)
y = table(["处理","鲜活回声","继续保留"],[
    ["收入心舍","有空位时带走新回声","发现记录与已学技艺"],
    ["只留记录","归档新回声，原有回声不变","新发现的事实、修复与技艺"],
    ["替换旧回声","带走新回声，归档所选旧回声","新旧事实记录与全部已学技艺"],
],[90,205,WIDTH-295],y)
y = heading("操作和保存边界",y)
y = p("确认归档后，完整的私人回声不再随身唤回；重访只能回看已经发生的事，不能重新领取或改写选择。最后一张终章页记录旅途，不占用鲜活回声的位置。",y)-14
y = p("静态谜题不限尝试次数，错放、转反或拓显不足不扣侵蚀。正确构件与已完成拓显区域逐步保存。守护失败可免费重试，修复、技艺与已确认取舍保留。",y)-16
y = p("实体修复与私人回应分开：归档宁安不会撤走玩家放下的空碗；归档承香不会拆掉已经接合的梁；归档回春后仍然可以敲响真实的鼓。",y)
c.showPage()

y = start(3,"一檐容人代表章节","三种操作各自回答一个生活问题，避免连续重复同一种描摹或选择题。")
rows = [
    ("joinery-detail-after.png","香火断","先让梁稳下来，再比对榫口、刻痕与方向。左右两端都能先装，中部需要两端接住，最后撤撑。缺损件可看，不能硬塞进合法槽口。","结构判断有可解释的依据，修复后仍看得见旧拼缝。"),
    ("guest-after.png","檐下客","看过旧碗与蓑衣后，把空碗放到檐下的空处。多个干地落点都成立；檐外或挤住旧碗时可继续尝试。实际位置会保存。","留位是玩家对往事的回应，不是猜一个精确像素。"),
    ("rubbing-partial.png","社鼓声","在鼓面施用藻井，再拓显外环、中央纹与旧修补线。每区有效覆盖达到 65% 即可收笔；停在一处或画布外乱涂不能替代拓显。","呈现已有纹样和旧修补痕，不让玩家凭空重画文物。"),
]
for filename,title,body,meaning in rows:
    y = heading(title,y)
    image(SHOTS/filename,LEFT,y,246,"真实 EXE 运行节选")
    right_y = p(body,y,LEFT+266,WIDTH-266)-10
    p(meaning,right_y,LEFT+266,WIDTH-266,"small")
    y -= 172
p("三段均支持替代输入：点击选件与槽口，键盘移动空碗，按住回车辅助拓显。鼓纹为谱页感应出的记忆图纹，机关为游戏化简化。",y,style="small")
c.showPage()

y = start(4,"取舍后让玩家主动听见差别","记录仍可查，刚修好的生活用途也仍然存在。")
half = (WIDTH-14)/2
image(SHOTS/"first-choice.png",LEFT,y,half,"首个满额选择 心舍 3 / 3")
image(SHOTS/"drum-response.png",LEFT+half+14,y,half,"确认后主动敲鼓 本页节选为归档宁安")
y -= half*9/16+43
y = table(["归档对象","退出的私人回应","仍然存在"],[
    ["檐 平安","归人脚步与随身唤回的灯影","桥的记录与斗拱技艺"],
    ["社 承香","抬梁手影与专属回声" if REV != "A3" else "抬梁记忆的暖迹与专属回声","已经接合的梁与手艺"],
    ["社 宁安","空碗的记忆暖影与那一夜客声","玩家放下的实体空碗"],
    ["新回声 社 回春","专属童声的数拍跟随","真实鼓声、发现记录与技艺"],
],[97,218,WIDTH-315],y)
y = p("确认选择后，玩家还要亲手敲一下鼓。正常鼓声始终响起；只有回春仍鲜活时，孩子才再次接上数拍。完成回应后，心舍才从三格展开为四格。",y)-16
y = p("四个分支已通过自动规则和界面检查。本页呈现真实实现与可复现后果，尚未把这些检查写成玩家情绪或理解的结论。",y,style="small")
c.showPage()

y = start(5,"保持已有材料的一致性","以现有封面、古建场景、纸墨界面和拓片为参照，采用灰黑、暖灰、纸白与少量朱金。")
y = image(ROOT/"output/设计方案/檐下千秋-回响版-v1/美术基准-2026-11-03.png",LEFT,y,WIDTH,"美术基准板 由既有与参考编辑资产排版 此图不是玩法实机截图")
y = heading("从参考到运行校正" if REV != "A3" else "两项真实制作与修订",y)
y = p("人物：从封面同一拓印师延展出完整站姿，再以该站姿参考生成行走和抬笔关键姿态。回响版调查、守护与残影统一成年比例；采用三个关键姿态加运行变化，不宣称十八帧新动画。",y)-12
y = p("物件：核对原图发现蓑衣热点实际画成扫帚，已局部补正；补入两双筷子、清晰饭碗近景与三结红绳。抬梁手影独立于实体梁，取舍前可查看，归档时消退。所有近看均可主动返回场景。" if REV != "A3" else "梁架：以原正殿固定构图修订色调；生成梁后补图，只在原梁位置的局部遮罩使用。首轮实机发现梁端遮罩不足，按运行边缘修正后再次渲染。其他建筑与家具继续取自母图。",y)-15
y = table(["采用资产","实际原生尺寸","处理方式"],[
    ["人物三姿态","各 1024×1536 RGBA","内置生图参考编辑"],
    ["正殿与梁后补图","各 1672×941 RGB","母图参考编辑与运行遮罩"],
    ["手影 / 鼓槌 / 饭碗近景" if REV != "A3" else "空碗与鼓面","各 1536×1024 RGBA" if REV != "A3" else "1536×1024 与 1254×1254","参考同一场景物件与纸墨质感"],
],[120,180,WIDTH-300],y)
p("本轮人工反馈明确玩法缺口、素材一致与避免深绿；AI 协助方案细化、参考编辑、实现和自动检查。工具未返回可核实的图像底层模型标识，未补写猜测。专属童声复用旧录音，新增鼓声和远锣为程序合成，非真人演奏。",y,style="small")
c.showPage()

y = start(6,"运行验证与交付范围",f"本说明对应回响版 {REV} 预览 已验证程序包与正式 U 盘材料不是同一个完成状态。")
y = heading("启动与操作",y)
y = p("完整解压文件夹，保留同目录 server 文件夹，双击“檐下千秋.exe”。无需安装 Godot 或 Go，也无需联网。程序内置回响版标识，自动启动本机配套服务，退出时关闭。",y)-12
y = p("鼠标点击或拖动；木件可用 Tab、回车与 R 转向。空碗可用方向键和回车。拓显可按住回车累计 1.5 秒辅助完成当前区域；守护准备好后开始，用数字键 1 至 5 或按钮。",y)-12
if REV != "A3":
    y = p("主页的“路演片段”可进入接梁或取舍节点。每次新开复制一份独立起点，操作仍可保存；演示进度、阅读记录和设置位于 demo 子目录，不改写正常旅程。",y)-12
y = p("存档位于 %APPDATA%\\Godot\\app_userdata\\檐下千秋\\echo-v1-save.json，与原版旅程分开。请勿同时打开两个回响版窗口。设置中可调整声音、全屏与环境动态。",y)-20
y = heading("已经检查的事实",y)
y = table(["检查范围","证据与结果"],[
    ["规则与保存","三到四到五格、四种取舍、技艺保留、终章页不占格、免费恢复与旧档保护"],
    ["客户端流程","十任务衔接与重载通过；后三章描摹和战斗采用确定输入，不替代初见体验"],
    ["真实程序包","隔离目录解压 EXE，自动识别回响版，配套服务自动启停，十任务可达并保存，终章页不占心舍" if verification.get("full_journey") else "隔离目录解压 EXE，自动识别回响版，配套服务自动启停，四任务完成后保存为四格"],
    ["演示与文件" if REV != "A3" else "画面与文件","接梁与取舍可操作；重复新开取舍验证独立进度，正常两版存档与设置字节不变；原生尺寸、文件哈希和退出日志通过" if REV != "A3" else "本说明实机节选来自同一 EXE 的 1920×1080 渲染；包内逐文件哈希、ZIP CRC 与退出日志检查通过"],
],[115,WIDTH-115],y)
y = heading("仍需完成的工作",y)
y = p("仍需真人体验：榫口是否易懂、空碗是否表达留位，以及归档的差别是否清楚。\n已制作同一版两分钟实机节选与六页 PPT；录屏为两个独立起点的自动输入操作。声音、动作、现场播放及匿名提交目录仍待最终核对。" if REV in ["A10","A11"] else ("仍需真人体验：榫口是否易懂、空碗是否表达留位，以及归档的差别是否清楚。\n声音、动作与现场设备待实测。录屏、PPT 与最终匿名提交目录尚未完成。" if REV != "A3" else "实际操作中是否看懂榫口、是否感到空碗在给人留位、是否理解失去哪个回应，仍需真人体验。听感、动作流畅度与现场设备也需实际检查。演示存档、完整录屏、汇报 PPT 及最终匿名提交目录尚未完成。"),y)-12
y = p("参赛材料按组委会提供的三个 final 内容清单组织，原选拔包保留。作品演示与汇报控制在五分钟内，含提问总计不超过八分钟；正式材料不出现学校或参赛人员信息。",y,style="small")-10
p("对应程序包 SHA256  " + verification["archive_sha256"],y,style="small")
c.showPage()
c.save()

document = pdfium.PdfDocument(str(FILE))
assert len(document) == 6
for i in range(len(document)):
    page = document[i]
    page.render(scale=1.65).to_pil().save(QA/f"page-{i+1}.png")
text = "\n".join(document[i].get_textpage().get_text_range() for i in range(len(document)))
assert "65%" in text and "回响版" in text and "真人体验" in text
assert "C:\\Users" not in text and "Admin" not in text
(QA/"source.json").write_text(json.dumps({"pdf":str(FILE),"pages":6,"evidence":str(evidence),"archive_sha256":verification["archive_sha256"]},ensure_ascii=False,indent=2),encoding="utf-8")
print(FILE)
