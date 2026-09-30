"""Qwen character references and action sheets; first two standard, then Pro.

Credentials stay in memory. Logs retain prompt, model, reference hashes and output
hashes, never credentials, encoded image inputs or signed download URLs.
"""
from pathlib import Path
from datetime import datetime
import os, json, re, base64, urllib.request, urllib.error, hashlib, argparse

ROOT=Path(__file__).resolve().parents[1]
DEST=ROOT/'output/imagegen/characters-20260930'
REFERENCE=ROOT/'Task02/Original-new/生成图片/主角'

def credential():
    value=os.environ.get('DASHSCOPE_API_KEY')
    if value: return value
    if os.name=='nt':
        import winreg
        for hive,path in [(winreg.HKEY_CURRENT_USER,'Environment'),(winreg.HKEY_LOCAL_MACHINE,r'SYSTEM\CurrentControlSet\Control\Session Manager\Environment')]:
            try:
                with winreg.OpenKey(hive,path) as entry: value=winreg.QueryValueEx(entry,'DASHSCOPE_API_KEY')[0]
                if value: return value
            except OSError: pass
    raise RuntimeError('DASHSCOPE_API_KEY is not configured; configure it locally before continuing.')

def sha(data): return hashlib.sha256(data).hexdigest()

def jobs():
    invariant='保持参考图中同一位男性拓印师的设计：黑色高髻与长黑发带，黑灰水墨外袍，米白交领与宽袖，青灰色腰坠、深色长靴，右手毛笔、左手墨色册页。脸型、衣服花纹、发髻和配饰必须一致，不增加其他人物或现代配饰。绘画风格保持国风水墨游戏原画，黑灰白色调。'
    result=[
      {'name':'hero-hd','reference':'檐下千秋主角.png','size':'1920*1080','prompt':invariant+'按参考图重新绘制原生高清全身角色设计稿。保持参考的正常成人比例与原站姿，人物完整从发髻到鞋底，居中，纯白无纹理背景。人物高度约950像素，宽袖和发带完整。精细重绘线条、面部、布料褶皱和毛笔，不使用模糊放大。不要标题、标注、分镜、边框或文字。'},
      {'name':'hero-chibi-hd','reference':'檐下千秋主角Q版.png','size':'1920*1080','prompt':invariant+'按参考图重新绘制同一人物的Q版高清全身角色设计稿，保持原有大头、小身体比例以及黑色发髻、大眼睛、宽袖和衣服层次。单个角色居中，纯白无纹理背景，完整站姿、完整鞋底，角色高度約950像素。册页用墨色封面、米白竖向封签，不写任何文字。不要标题、标注、分镜、边框或水印。'}]
    phases={
      'walk':['右脚向前落地、左腿向后','身体稍向下、右脚承重','左腿从身下向前经过','左脚向前落地、右腿向后','身体稍向下、左脚承重','右腿从身下向前经过'],
      'attack':['毛笔收向右肩蓄力、身体微转','手臂向后达到最高蓄力','手臂和毛笔挥向前方右侧','挥笔到最前方，宽袖展开','收回毛笔，身体回正','恢复战斗站姿'],
      'hurt':['正常战斗站姿','肩部轻微向后受击','上身后仰最深、眉头微皱','身体略微蜷缩缓冲','重新站直','恢复原站姿']}
    for state,poses in phases.items():
        prompt=invariant+'以参考Q版角色为唯一人物，绘制可直接用于2D游戏的六帧'+{'walk':'走路','attack':'挥笔攻击','hurt':'受击恢复'}[state]+'动作精灵图集。整张图1920×1280，严格三列两行，六个等大的640×640单元格，不画单元格边框，不加文字。顺序先上排左中右，再下排左中右。每格只有一个同样大小的完整角色，朝右侧的三分之四视角；固定镜头、固定头部大小，角色约460像素高，脚底在本格y=570附近。人物完全留在单元格内，发带和宽袖不得碰到边缘。严格纯白RGB(255,255,255)背景，不要阴影、地面、特效、速度线。六帧必须有真实手臂与腿部姿态变化，不能六次复制同一个站姿。按顺序分别是：'+ '；'.join(f'第{i+1}格：{pose}' for i,pose in enumerate(poses))+'。保持衣服和配饰一致。册页封签不写文字。'
        result.append({'name':'hero-'+state+'-sheet','reference':'檐下千秋主角Q版.png','size':'1920*1280','prompt':prompt})
    result.append({'name':'hero-hd-reframed','reference':'output/imagegen/characters-20260930/hero-hd.png','size':'1920*1080','prompt':invariant+'依据参考图保持同一成人角色和相同水墨绘画细节，将人物完整安排在1920×1080白色画布内。必须补全双脚鞋底，人物高度约880像素，头顶到图片顶部至少80像素，鞋底到图片底部至少80像素。保留完整毛笔、册页、发带和宽袖，正常成人比例，原站姿，不得截切脚或发髻。只重新调整画面构图并补全鞋底细节，不更换脸、衣服和人物设计。纯白背景，不加文字、水印或边框。'})
    for i,job in enumerate(result): job['model']='qwen-image-3.0' if i<2 else 'qwen-image-3.0-pro'
    return result

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--only');parser.add_argument('--dry-run',action='store_true');args=parser.parse_args()
    DEST.mkdir(parents=True,exist_ok=True)
    all_jobs=jobs();(DEST/'prompts.json').write_text(json.dumps(all_jobs,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    if args.dry_run:
        print(json.dumps([{'name':j['name'],'model':j['model'],'size':j['size']} for j in all_jobs],ensure_ascii=False));return
    key=credential()
    for j in all_jobs:
        if args.only and j['name']!=args.only: continue
        output=DEST/(j['name']+'.png');meta=DEST/(j['name']+'.json')
        if output.exists() and meta.exists(): print('Already generated: '+j['name'],flush=True);continue
        reference=(ROOT/j['reference']) if j['reference'].startswith('output/') else (REFERENCE/j['reference']);raw=reference.read_bytes()
        payload={'model':j['model'],'input':{'messages':[{'role':'user','content':[{'image':'data:image/png;base64,'+base64.b64encode(raw).decode()},{'text':j['prompt']}]}]},'parameters':{'size':j['size'],'n':1,'watermark':False}}
        req=urllib.request.Request('https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation',data=json.dumps(payload,ensure_ascii=False).encode(),headers={'Authorization':'Bearer '+key,'Content-Type':'application/json','X-DashScope-Async':'disable'})
        print('Generating '+j['name']+' with '+j['model'],flush=True)
        try:
            with urllib.request.urlopen(req,timeout=600) as response: data=json.load(response)
        except urllib.error.HTTPError as error:
            detail=error.read().decode('utf8','replace');detail=re.sub(r'sk-[A-Za-z0-9._-]+','[REDACTED]',detail)
            detail=re.sub(r'https?://\S+','[URL]',detail)
            raise RuntimeError(f'{j["name"]}: HTTP {error.code}: {detail[:600]}') from None
        content=data['output']['choices'][0]['message']['content']
        url=next(x['image'] for x in content if x.get('image'))
        # Signed result URL is not logged, and the API credential is not forwarded.
        with urllib.request.urlopen(url,timeout=120) as response: blob=response.read()
        output.write_bytes(blob)
        record={**j,'time':datetime.now().isoformat(timespec='seconds'),'reference_sha256':sha(raw),'output_sha256':sha(blob),'bytes':len(blob),'request_id':data.get('request_id'),'usage':data.get('usage'),'workflow':'existing DashScope multimodal image generation API with a reference image'}
        meta.write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
        print('Saved '+output.name+' ('+str(len(blob))+' bytes)',flush=True)

if __name__=='__main__': main()
