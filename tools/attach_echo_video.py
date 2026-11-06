"""Attach native Open XML video to the Artifact Tool-authored slide 3.

No python-pptx authoring is used. Other slide objects remain unchanged.
"""
from pathlib import Path
import hashlib,json,zipfile
from lxml import etree as E

ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/'.review/echo-ppt'
SOURCE=BUILD/'candidate-without-video.pptx'
VIDEO=ROOT/'output/决赛修订材料/回响版A11/檐下千秋_两分钟实机节选.mp4'
POSTER=BUILD/'movie-poster.png'
DEST=BUILD/'candidate-with-video.pptx'
NS={'p':'http://schemas.openxmlformats.org/presentationml/2006/main',
    'a':'http://schemas.openxmlformats.org/drawingml/2006/main',
    'r':'http://schemas.openxmlformats.org/officeDocument/2006/relationships',
    'p14':'http://schemas.microsoft.com/office/powerpoint/2010/main',
    'rels':'http://schemas.openxmlformats.org/package/2006/relationships',
    'ct':'http://schemas.openxmlformats.org/package/2006/content-types'}
for prefix,uri in NS.items(): E.register_namespace(prefix,uri)
def q(name):
    prefix,local=name.split(':');return '{'+NS[prefix]+'}'+local
def sub(parent,tag,attrs=None):return E.SubElement(parent,q(tag),attrs or {})
with zipfile.ZipFile(SOURCE) as source: parts={n:source.read(n) for n in source.namelist()}
slide=E.fromstring(parts['ppt/slides/slide3.xml'])
tree=slide.find('p:cSld/p:spTree',NS)
for child in list(tree):
    if E.QName(child).localname not in ['nvGrpSpPr','grpSpPr']:tree.remove(child)
pic=sub(tree,'p:pic')
nv=sub(pic,'p:nvPicPr')
props=sub(nv,'p:cNvPr',{'id':'900','name':'两分钟实机节选','descr':'两个独立起点的实际程序操作，自动输入；点击播放'})
sub(props,'a:hlinkClick',{'action':'ppaction://media'})
sub(sub(nv,'p:cNvPicPr'),'a:picLocks',{'noChangeAspect':'1'})
app=sub(nv,'p:nvPr')
sub(app,'a:videoFile',{q('r:link'):'rIdEchoVideo'})
extension=sub(sub(app,'p:extLst'),'p:ext',{'uri':'{DAA4B4D4-6D71-4841-9C94-3DE7FCFB9230}'})
sub(extension,'p14:media',{q('r:embed'):'rIdEchoMedia'})
fill=sub(pic,'p:blipFill')
sub(fill,'a:blip',{q('r:embed'):'rIdEchoPoster'})
sub(sub(fill,'a:stretch'),'a:fillRect')
shape=sub(pic,'p:spPr')
transform=sub(shape,'a:xfrm')
sub(transform,'a:off',{'x':'0','y':'0'})
sub(transform,'a:ext',{'cx':'12192000','cy':'6858000'})
sub(sub(shape,'a:prstGeom',{'prst':'rect'}),'a:avLst')
existing=slide.find('p:timing',NS)
if existing is not None:slide.remove(existing)
timing=sub(slide,'p:timing')
tn=sub(sub(sub(timing,'p:tnLst'),'p:par'),'p:cTn',{'id':'1','dur':'indefinite','restart':'never','nodeType':'tmRoot'})
media=sub(sub(sub(tn,'p:childTnLst'),'p:video'),'p:cMediaNode',{'vol':'100000'})
play=sub(media,'p:cTn',{'id':'2','fill':'hold','display':'0'})
sub(sub(play,'p:stCondLst'),'p:cond',{'delay':'indefinite'})
sub(sub(media,'p:tgtEl'),'p:spTgt',{'spid':'900'})
parts['ppt/slides/slide3.xml']=E.tostring(slide,xml_declaration=True,encoding='UTF-8',standalone=True)
rels=E.fromstring(parts['ppt/slides/_rels/slide3.xml.rels'])
for identity,kind,target in [
 ('rIdEchoVideo',NS['r']+'/video','../media/echo-demo.mp4'),
 ('rIdEchoMedia','http://schemas.microsoft.com/office/2007/relationships/media','../media/echo-demo.mp4'),
 ('rIdEchoPoster',NS['r']+'/image','../media/echo-demo-poster.png')]:
    sub(rels,'rels:Relationship',{'Id':identity,'Type':kind,'Target':target})
parts['ppt/slides/_rels/slide3.xml.rels']=E.tostring(rels,xml_declaration=True,encoding='UTF-8',standalone=True)
types=E.fromstring(parts['[Content_Types].xml'])
if not any(n.get('Extension')=='mp4' for n in types):sub(types,'ct:Default',{'Extension':'mp4','ContentType':'video/mp4'})
parts['[Content_Types].xml']=E.tostring(types,xml_declaration=True,encoding='UTF-8',standalone=True)
parts['ppt/media/echo-demo.mp4']=VIDEO.read_bytes()
parts['ppt/media/echo-demo-poster.png']=POSTER.read_bytes()
core=E.fromstring(parts['docProps/core.xml'])
for item in core:
    if E.QName(item).localname in ['creator','lastModifiedBy']:item.text=''
parts['docProps/core.xml']=E.tostring(core,xml_declaration=True,encoding='UTF-8',standalone=True)
for name,data in parts.items():
    if name.endswith('.xml'):
        text=data.decode('utf-8')
        if 'C:\\Users' in text or '/Users/' in text or 'Admin' in text:raise RuntimeError('Personal path in presentation XML: '+name)
with zipfile.ZipFile(DEST,'w',compression=zipfile.ZIP_DEFLATED) as output:
    for name,data in parts.items():output.writestr(name,data)
receipt={'authored_with':'@oai/artifact-tool','native_video_slide':3,'embedded_sha256':hashlib.sha256(VIDEO.read_bytes()).hexdigest(),
         'sources':['https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.presentation.commonmedianode',
                    'https://github.com/scanny/python-pptx/blob/master/docs/dev/analysis/shp-movie.rst'],
         'playback':'on click in slide show','slides':6}
(BUILD/'media-attachment.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2),encoding='utf-8')
print(DEST)
