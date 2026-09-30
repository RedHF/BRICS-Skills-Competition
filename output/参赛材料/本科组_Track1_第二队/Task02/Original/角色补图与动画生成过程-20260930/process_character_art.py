"""Slice generated Qwen action atlases, remove border-connected white matte,
and align transparent character frames to one consistent foot baseline."""
from pathlib import Path
from collections import deque
from PIL import Image, ImageDraw
import json,hashlib,statistics
ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'output/imagegen/characters-20260930'
TARGET=ROOT/'LLM-tmp/客户端/assets/characters'

def cutout(image):
    image=image.convert('RGBA');w,h=image.size;pixels=list(image.get_flattened_data())
    background=bytearray(int(min(c[:3])>=228) for c in pixels)
    seen=bytearray(w*h);pending=deque()
    for x in range(w):pending.extend([x,(h-1)*w+x])
    for y in range(h):pending.extend([y*w,y*w+w-1])
    while pending:
        i=pending.popleft()
        if seen[i] or not background[i]:continue
        seen[i]=1;x=i%w;y=i//w
        if x:pending.append(i-1)
        if x<w-1:pending.append(i+1)
        if y:pending.append(i-w)
        if y<h-1:pending.append(i+w)
    image.putdata([(*c[:3],0 if seen[i] else c[3]) for i,c in enumerate(pixels)])
    return image

def main():
    TARGET.mkdir(parents=True,exist_ok=True)
    cells=[]
    for state in ['walk','attack','hurt']:
        src=SOURCE/('hero-'+state+'-sheet.png');atlas=Image.open(src)
        assert atlas.size==(1920,1280),(src,atlas.size)
        for i in range(6):
            col,row=i%3,i//3
            cell=cutout(atlas.crop((col*640,row*640,(col+1)*640,(row+1)*640)))
            bbox=cell.getchannel('A').getbbox();assert bbox is not None
            cells.append((state,i,cell,bbox))
    median=statistics.median(b[3]-b[1] for _,_,_,b in cells)
    factor=min(1,480/median)
    result=[]
    for state,i,cell,bbox in cells:
        cropped=cell.crop(bbox);scaled=cropped.resize((round(cropped.width*factor),round(cropped.height*factor)),Image.Resampling.LANCZOS)
        frame=Image.new('RGBA',(640,640));frame.alpha_composite(scaled,((640-scaled.width)//2,570-scaled.height))
        path=TARGET/f'{state}_{i}.png';frame.save(path,optimize=True)
        result.append({'file':path.relative_to(ROOT).as_posix(),'state':state,'frame':i,'source':f'hero-{state}-sheet.png','source_cell':[i%3,i//3],'source_bounds':list(bbox),'common_scale':factor,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
    # Idle comes from the accepted high-resolution chibi design, not a walk frame.
    idle=cutout(Image.open(SOURCE/'hero-chibi-hd.png'));idle=idle.crop(idle.getchannel('A').getbbox())
    idle.thumbnail((480,480),Image.Resampling.LANCZOS)
    canvas=Image.new('RGBA',(640,640));canvas.alpha_composite(idle,((640-idle.width)//2,570-idle.height));canvas.save(TARGET/'idle.png',optimize=True)
    result.append({'file':(TARGET/'idle.png').relative_to(ROOT).as_posix(),'state':'idle','source':'hero-chibi-hd.png','sha256':hashlib.sha256((TARGET/'idle.png').read_bytes()).hexdigest()})
    contact=Image.new('RGB',(1920,960),(235,228,210));draw=ImageDraw.Draw(contact)
    for row,state in enumerate(['walk','attack','hurt']):
        animation=[]
        for i in range(6):
            frame=Image.open(TARGET/f'{state}_{i}.png').convert('RGBA')
            tile=frame.resize((320,320),Image.Resampling.LANCZOS)
            contact.paste(tile,(i*320,row*320),tile);draw.text((i*320+10,row*320+10),state+' '+str(i),fill='black')
            bg=Image.new('RGBA',(640,640),(235,228,210,255));bg.alpha_composite(frame);animation.append(bg.convert('RGB'))
        animation[0].save(SOURCE/(state+'-preview.gif'),save_all=True,append_images=animation[1:],duration=100,loop=0)
    contact.save(SOURCE/'frames-contact.jpg',quality=94)
    (SOURCE/'frame-processing.json').write_text(json.dumps({'method':'border-connected white removal, six cells per 3x2 atlas; shared scale and foot baseline; no invented image frames','frames':result},ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    print('Prepared 18 distinct animation frames and one idle sprite')

if __name__=='__main__':main()
