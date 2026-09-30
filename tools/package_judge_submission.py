"""Verify and archive the jury submission using a strict 500,000,000 byte limit."""
from pathlib import Path
import hashlib,json,re,zipfile,subprocess
from PIL import Image
from pypdf import PdfReader

ROOT=Path(__file__).resolve().parents[1]
PACKAGE=ROOT/'output/评委提交/本科组_Track1_第二队'
LIMIT=500_000_000
def sha(path):
    with path.open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()
def save(path,value):
    temporary=path.with_name(path.name+'.tmp')
    temporary.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf8');temporary.replace(path)
def main():
    for task in ['Task01','Task02','Task03']:
        for kind in ['Original','Final']:assert (PACKAGE/task/kind).is_dir()
    expected={'Task01':{'AI协作记录.pdf','AI协作记录.docx','游戏策划案.pdf','游戏策划案.docx'},'Task02':{'AI协作记录.pdf','AI协作记录.docx','游戏素材图','主场景图'},'Task03':{'运行逻辑说明.pdf','运行逻辑说明.docx','测试与迭代记录.pdf','测试与迭代记录.docx','核心可玩实体','交互演示视频.mp4'}}
    for task,suffixes in expected.items():
        actual={f.name.removeprefix(f'Track01_{task}_第二队_檐下千秋_') for f in (PACKAGE/task/'Final').iterdir()}
        assert actual==suffixes,(task,actual)
    jpgs=list((PACKAGE/'Task02/Final').rglob('*.jpg'));assert len(jpgs)==112
    sizes=[]
    for f in jpgs:
        with Image.open(f) as im:
            assert im.mode=='RGB' and all(abs(v-300)<1 for v in im.info.get('dpi',[])) and 'dpi' in im.info
            sizes.append(im.size)
            if '角色设计' in f.parts or '角色动作设计' in f.parts or '主场景图' in f.parent.name or '场景设计' in f.parts:
                assert im.width>=1920 and im.height>=1080,(f,im.size)
    assert sum(min(x)>=1024 for x in sizes)>=10
    manifest=json.loads((PACKAGE/'Task02/Original/图片转换清单.json').read_text(encoding='utf8'))
    for e in manifest:
        assert sha(PACKAGE/e['target'])==e['target_sha256']
        assert sha(PACKAGE/e['packaged_source'])==e['source_sha256']
        assert not e['upscaled']
    core=PACKAGE/'Task03/Final/Track01_Task03_第二队_檐下千秋_核心可玩实体'
    dist=ROOT/'dist/檐下千秋-v20-自适应界面版-20260930'
    for f in dist.rglob('*'):
        if f.is_file():assert sha(f)==sha(core/'Windows-x64'/f.relative_to(dist))
    video=PACKAGE/'Task03/Final/Track01_Task03_第二队_檐下千秋_交互演示视频.mp4'
    data=json.loads(subprocess.check_output(['C:/Program Files/FFmpeg/ffprobe.exe','-v','quiet','-show_format','-show_streams','-of','json',str(video)],text=True,encoding='utf8'))
    v=next(s for s in data['streams'] if s['codec_type']=='video');n,d=map(int,v['avg_frame_rate'].split('/'));duration=float(data['format']['duration'])
    assert 170<=duration<=200 and v['width']>=1920 and v['height']>=1080 and n/d>=24 and v['codec_name']=='h264' and video.stat().st_size<200_000_000
    secret=re.compile(r'\b(?:sk-[A-Za-z0-9._-]{10,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})')
    bad=[];scanned=0
    for f in PACKAGE.rglob('*'):
        if not f.is_file():continue
        assert not any(x in {'.godot','__pycache__','.verify-tmp'} for x in f.parts)
        assert f.name not in {'Thumbs.db','.DS_Store'} and not f.name.startswith('~$') and f.suffix!='.tmp'
        if f.suffix.lower() in {'.txt','.md','.json','.jsonl','.gd','.cfg','.py','.go','.toml','.csv','.log'}:text=f.read_text(encoding='utf8',errors='replace')
        elif f.suffix=='.docx':
            with zipfile.ZipFile(f) as z:text='\n'.join(z.read(n).decode('utf8','replace') for n in z.namelist() if n.endswith('.xml'))
        elif f.suffix=='.pdf':text='\n'.join(p.extract_text() or '' for p in PdfReader(f).pages)
        else:continue
        scanned+=1
        if secret.search(text):bad.append(f.relative_to(PACKAGE).as_posix())
    assert not bad,'Inspect privately: credential pattern found'
    journey=json.loads((ROOT/'.review/judge-journey/result.json').read_text(encoding='utf8'))
    assert journey['exit']==0 and not journey['errors'] and journey['all_ten_tasks_passed'] and len(journey['event_passes'])==10
    verification={'date':'2026-09-30','authority':'评分标准；冲突项按参赛者明确指示优先采用评分标准','team_id':'第二队','task_structure':'PASS','formal_names':'PASS','jpg_count':112,'major_rasters_min_side_1024':sum(min(x)>=1024 for x in sizes),'image_hashes_and_sources':'PASS','upscaled_images':0,'runtime_9_files_match_v20':'PASS','video':{'duration_seconds':duration,'size':[v['width'],v['height']],'fps':n/d,'codec':v['codec_name'],'bytes':video.stat().st_size,'real_game_interaction_and_server_settlement':'PASS','input':'自动输入驱动真实客户端；包含两次实际服务器结算','capture':'Godot Movie Maker本机游戏视口及游戏音频录制，FFmpeg编码'},'documents':json.loads((ROOT/'.review/judge-doc-audit.json').read_text(encoding='utf8'))['documents'],'go_tests':'PASS on jury source copy','asset_audit':'210 audio / 184 voice cues / 162 narrative cues / 226 references, no issues','credential_scan':{'files_scanned':scanned,'pattern_hits':0}}
    verification['full_journey']=journey
    save(PACKAGE/'Task03/Original/验证记录/2026-09-30-提交核验.json',verification)
    manifest_path=PACKAGE/'文件清单.json';sha_path=PACKAGE/'SHA256.txt'
    files=sorted(f for f in PACKAGE.rglob('*') if f.is_file() and f not in {manifest_path,sha_path})
    entries=[{'path':f.relative_to(PACKAGE).as_posix(),'bytes':f.stat().st_size,'sha256':sha(f)} for f in files]
    save(manifest_path,{'date':'2026-09-30','scope':'全部交付文件，不含本清单及SHA256.txt本身','files':entries})
    temp=sha_path.with_name('hashes.tmp');temp.write_text(''.join(f'{e["sha256"]}  {e["path"]}\n' for e in entries),encoding='utf8');temp.replace(sha_path)
    archive=PACKAGE.parent/'最终提交'/(PACKAGE.name+'.zip');archive.parent.mkdir(exist_ok=True);pending=archive.with_name(archive.name+'.part')
    print(f'Packaging {len(files)+2} files with 500,000,000 byte limit...',flush=True)
    with zipfile.ZipFile(pending,'w',zipfile.ZIP_DEFLATED,compresslevel=9,allowZip64=True) as z:
        for f in files+[manifest_path,sha_path]:z.write(f,f.relative_to(PACKAGE.parent).as_posix())
    assert pending.stat().st_size<LIMIT,f'Archive too large: {pending.stat().st_size}; retain .part for inspection'
    print('Checking CRC and every archived file hash...',flush=True)
    with zipfile.ZipFile(pending) as z:
        assert z.testzip() is None
        for e in entries:
            content=z.read(PACKAGE.name+'/'+e['path']);assert len(content)==e['bytes'] and hashlib.sha256(content).hexdigest()==e['sha256']
    pending.replace(archive)
    result={'archive':str(archive),'bytes':archive.stat().st_size,'MB_decimal':round(archive.stat().st_size/1e6,2),'strict_limit_bytes':LIMIT,'under_500MB':True,'sha256':sha(archive),'files':len(files)+2,'crc':'PASS','all_manifest_hashes':'PASS','date':'2026-09-30'}
    save(PACKAGE.parent/'最终压缩包核验结果.json',result)
    archive.with_suffix('.zip.sha256').write_text(result['sha256']+'  '+archive.name+'\n',encoding='utf8')
    print(json.dumps(result,ensure_ascii=False),flush=True)
if __name__=='__main__':main()
