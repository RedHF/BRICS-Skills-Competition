"""A reviewable art process booklet made from adopted assets and real captures."""
from pathlib import Path
from xml.sax.saxutils import escape
import json,sys,hashlib
from PIL import Image
import pypdfium2 as pdfium
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import Paragraph,Table,TableStyle
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.utils import ImageReader
from reportlab.lib import colors

ROOT=Path(__file__).resolve().parents[1]
ART=ROOT/'LLM-tmp/客户端/assets'
ADOPTED=ART/'echo_v1'
EVIDENCE=ROOT/'LLM-tmp/验证记录/2026-11-04-回响版'
SHOTS=EVIDENCE/'033924-exported-client/frames'
BRANCH=EVIDENCE/'034952-exported-client/frames'
OUT=ROOT/'output/决赛修订材料/回响版A11'
QA=ROOT/'.review/echo-process-a11'
OUT.mkdir(parents=True,exist_ok=True);QA.mkdir(parents=True,exist_ok=True)
pdfmetrics.registerFont(TTFont('SC',str(ART/'fonts/NotoSerifSC-Regular.ttf')))
W,H=595.276,841.89;L,R=46,549.276;WIDTH=R-L
INK=colors.HexColor('#28241f');MUTED=colors.HexColor('#746b60');PAPER=colors.HexColor('#f6f1e8')
ST={k:ParagraphStyle(k,fontName='SC',fontSize=s,leading=h,textColor=col,wordWrap='CJK') for k,s,h,col in [('body',10.5,17,INK),('small',8.5,13.5,MUTED),('cell',9,14,INK),('head',9,14,colors.white)]}
FILE=OUT/'檐下千秋_视觉与AI制作过程册.pdf'
c=canvas.Canvas(str(FILE),pagesize=(W,H),pageCompression=1)
c.setTitle('檐下千秋回响版视觉与AI制作过程册');c.setAuthor('');c.setCreator('')

def p(text,y,x=L,width=WIDTH,style='body'):
    item=Paragraph(escape(text).replace('\n','<br/>'),ST[style]);_,h=item.wrap(width,1000)
    if y-h<49:raise ValueError(f'Overflow {text[:25]}')
    item.drawOn(c,x,y-h);return y-h
def head(text,y):
    c.setFont('SC',14);c.setFillColor(INK);c.drawString(L,y-14,text);return y-28
def page(n,title,subtitle):
    c.setFillColor(PAPER);c.rect(0,0,W,H,fill=1,stroke=0)
    c.setFont('SC',8.5);c.setFillColor(MUTED);c.drawString(L,H-52,'本科组 Track01');c.drawRightString(R,H-52,'回响版 A11  2026 11 04')
    c.setFont('SC',21);c.setFillColor(INK);c.drawString(L,H-94,title)
    y=p(subtitle,H-111,style='small')-22
    c.setFont('SC',8);c.setFillColor(MUTED);c.drawString(L,29,'檐下千秋 视觉与AI制作过程册');c.drawRightString(R,29,f'{n} / 4')
    return y
def picture(file,x,y,w,h,caption='',crop=None):
    im=Image.open(file)
    if crop:
        iw,ih=im.size;a,b,d,e=crop;im=im.crop((int(a*iw),int(b*ih),int(d*iw),int(e*ih)))
    iw,ih=im.size;factor=min(w/iw,h/ih);dw,dh=iw*factor,ih*factor
    c.drawImage(ImageReader(im),x+(w-dw)/2,y-(h-dh)/2-dh,width=dw,height=dh,mask='auto')
    if caption:p(caption,y-h-7,x,w,'small')
    return y-h-36
def table(headers,rows,widths,y):
    data=[[Paragraph(escape(s),ST['head']) for s in headers]]+[[Paragraph(escape(s),ST['cell']) for s in row] for row in rows]
    item=Table(data,colWidths=widths)
    item.setStyle(TableStyle([('BACKGROUND',(0,0),(-1,0),colors.HexColor('#39342e')),('ROWBACKGROUNDS',(0,1),(-1,-1),[colors.white,colors.HexColor('#eeeae2')]),('GRID',(0,0),(-1,-1),.5,colors.HexColor('#d9d9d9')),('VALIGN',(0,0),(-1,-1),'MIDDLE'),('LEFTPADDING',(0,0),(-1,-1),8),('RIGHTPADDING',(0,0),(-1,-1),8),('TOPPADDING',(0,0),(-1,-1),7),('BOTTOMPADDING',(0,0),(-1,-1),7)]))
    _,h=item.wrap(WIDTH,1000)
    if y-h<49:raise ValueError('Table overflow')
    item.drawOn(c,L,y-h);return y-h-20

y=page(1,'沿用原角色与纸墨质感','从现有参考出发，按单人可完成的范围补齐动作、物件和记忆回应。')
y=p('本轮由用户指出玩法不足与美术缺口，并明确“美术材料尽量和现有的保持一致”。制作以现有封面、古建场景、拓片和纸墨界面为参考；新增材料采用灰黑、暖灰、米白、旧木色与少量朱红，不加入深绿色主材。',y)-17
y=head('同一成年拓印师的三种关键姿态',y)
for i,(name,label) in enumerate([('artisan_standing.png','站立'),('artisan_walking.png','行走'),('artisan_casting.png','抬笔')]):
    picture(ADOPTED/name,L+i*169,y,155,239,label)
y-=280
y=p('先从原封面延展完整站姿，再以该站姿作为行走、抬笔的身份参考。脸型、发髻与头带、墨黑外袍和米白衣片保持一致，调查与守护都使用成年比例。三张为关键姿态，运行中配合位移和轻微变化；不把它们写成十八帧新动画。',y)-17
y=table(['环节','实际工作与采用依据'],[
 ['人的方向与约束','文化主题、玩法缺口、保持现有风格、避免深绿及单人执行约束'],
 ['AI 协助','方案细化、图像参考编辑、接入与自动检查；本轮图像使用内置 image_gen'],
 ['采用后的核对','透明度、人物比例、物件数量、线索位置以及实际程序显示'],
],[112,WIDTH-112],y)
p('工具未返回可核实的图像底层模型名称，因此只登记工具和实际输出。完整提示词与来源另存于本册配套的素材生成记录。',y,style='small');c.showPage()

y=page(2,'把线索补成看得见的物件','修正叙事和画面的不一致，近看必须提供玩家能够辨认的信息。')
half=(WIDTH-18)/2
picture(ART/'landscape/temple_guest.jpeg',L,y,half,168,'原图局部：被误标为蓑衣的扫帚',(.60,.50,.72,.82))
picture(SHOTS/'temple_guest-close-cape.png',L+half+18,y,half,168,'A11 实机近看局部：旧蓑衣与补丁',(.245,.185,.47,.855))
y-=205
y=p('在同一挂钩区域生成旧蓑衣补图；原门、墙、灯光和雨夜构图继续使用母图。饭碗处补入两双筷子，再生成同一饭碗的清晰近景，解决远景直接放大后的模糊。玩家移动的空碗仍是另一个独立物件。',y)-18
picture(ADOPTED/'guest_bowl_close.png',L,y,half,162,'旧饭碗与四根筷子 1536×1024 RGBA')
picture(ADOPTED/'drum_beater_three_knots.png',L+half+18,y,half,162,'鼓槌与三个绳结 1536×1024 RGBA')
y-=200
y=head('数量与用途在实际场景中复核',y)
y=p('三处绳结可以逐个数清，用来支持故事中的孩子跟拍；它是本作虚构线索，未冒称特定历史仪式。六处观察各有近看、明确返回与再次查看入口；近看期间阻止误触后方操作。母图上的原有 AI 来源标记没有为美观而抹去。',y)-14
p('参考文件：temple_guest.jpeg、temple_drum.jpeg。采用资产：temple_guest_detail_patch.png、guest_bowl_close.png、drum_beater_three_knots.png。生成参数、精确提示及尺寸见配套记录。',y,style='small');c.showPage()

y=page(3,'实体修复与私人记忆分开','两张均来自同一 A11 Windows 程序的实际运行；展示区域裁切自原生 1920×1080 画面。')
picture(SHOTS/'temple_incense-kept-response.png',L,y,half,178,'承香鲜活：梁下出现抬梁手影',(.016,.135,.49,.61))
picture(BRANCH/'choice-result.png',L+half+18,y,half,178,'确认归档承香后：梁与旧痕仍保留',(.016,.135,.49,.61))
y-=220
y=p('手影是独立的透明记忆层。选择前可以先看旧回应；归档时手影退出，实体梁、刻痕、拼缝和已学技艺保留。真实鼓声与孩子的私人跟拍也分别处理，玩家在取舍后亲手敲鼓，能够听见差别。',y)-18
y=head('生成之后还要检查实际尺寸',y)
y=table(['发现的问题','修订与证据'],[
 ['首轮梁后补图遮罩不足','根据实机左梁端残留修正运行遮罩，保留原柱、门和供桌'],
 ['手影素材正常，结果页却看不见','发现追加梁纹理后小尺寸手影消失；改为实体先画、记忆后画，并把指尖移到梁下'],
 ['状态为鲜活，不代表画面可见','在实际结果页切换仅用于检查的可见层，核对图像差异；A11 检出 8888 个可见差异像素'],
 ['归档不能拆除已修好的梁','真实 EXE 分支检查确认手影消退、实体画面仍在，相关画面见本页'],
],[132,WIDTH-132],y)
p('证据索引：033924-exported-client 与 034952-exported-client。前者覆盖十任务与保存，后者覆盖归档承香分支。检查属于自动操作，不作为真人的情绪、理解或手感结论。',y,style='small');c.showPage()

y=page(4,'提示词与来源可以追溯','以下保留抬梁手影的完整采用提示，其他采用资产的完整提示随配套记录保存。')
record=(ADOPTED/'线索与记忆层生成记录.md').read_text(encoding='utf-8')
prompt=record.split('## beam_lifting_hands.png',1)[1].split('### 最终提示词',1)[1].strip()
y=p('参考：temple_hall_master.png。内置 image_gen 参考生成，原生 1536×1024 RGBA；采用时保留原输出透明度。没有把概念图当作玩法截图。',y)-15
y=p(prompt,y,style='small')-20
y=head('声音与过程记录的口径',y)
y=p('专属童声继续采用项目原录音，新增单鼓和远锣为程序合成，不声称真人演奏。两分钟视频采用固定 A11 程序的两个独立起点，输入由自动脚本安排；片段标识、实际结果和原程序输出的声音保留。',y)-13
y=p('配套素材生成记录包含参考、完整提示、尺寸和采用范围。素材清单登记实际文件的 SHA256；旧选拔材料按原日期和原版本保留，决赛增补明确标识回响版范围。未发生的试玩、未提供的队员贡献及未核实的模型名称均不补写。',y)-15
p('本册用于解释制作决策与真实修订，不替代现场播放、扬声器听感和陌生玩家的实际操作。',y,style='small');c.showPage()
c.save()
doc=pdfium.PdfDocument(str(FILE))
if len(doc)!=4:raise ValueError('Unexpected page count')
for i,page_ in enumerate(doc):page_.render(scale=1.65).to_pil().save(QA/f'page-{i+1}.png')
texts='\n'.join(doc[i].get_textpage().get_text_range() for i in range(len(doc)))
if any(t in texts for t in ['上海商学院','Admin','C:\\Users']):raise ValueError('Identity leak')
(QA/'source.json').write_text(json.dumps({'pages':4,'archive_sha256':'6d9d50f7866311d6a6484eebc2ba670fdc70db4a47c03fd0e22b4e06163f672b','evidence':['033924-exported-client','034952-exported-client'],'pdf_sha256':hashlib.sha256(FILE.read_bytes()).hexdigest()},indent=2),encoding='utf-8')
sys.stdout.reconfigure(encoding='utf-8');print(FILE)
