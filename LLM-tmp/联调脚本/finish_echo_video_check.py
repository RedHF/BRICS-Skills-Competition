"""Recheck completed recording files after a metadata-decoding failure."""
from pathlib import Path
import json,sys
from record_echo_video import probe
import package_release as base
from verify_release import log_findings

root=base.ROOT
evidence=root/'LLM-tmp/验证记录/2026-11-04-回响版/021129-recorded-excerpts'
work=root/'.review/echo-movie/20261104-021129'
original=json.loads((evidence/'result.json').read_text(encoding='utf-8'))
if (evidence/'result-before-probe-fix.json').exists(): raise RuntimeError('Recovery already recorded')
(evidence/'result-before-probe-fix.json').write_text(json.dumps(original,ensure_ascii=False,indent=2),encoding='utf-8')
clips=[]
for mode,duration in [('repair',50),('choice',70)]:
    output=evidence/mode
    content=(output/'console.log').read_text(encoding='utf-8')
    errors=log_findings(content)
    if errors or f'PASS exported movie: {mode}' not in content: raise RuntimeError('Actual recording did not finish cleanly')
    record=json.loads((output/'frames.json').read_text(encoding='utf-8'))
    raw=work/f'{mode}.avi'
    metadata=probe(raw)
    video=next(s for s in metadata['streams'] if s['codec_type']=='video')
    if [video['width'],video['height']]!=[1920,1080]: raise RuntimeError('Wrong native dimensions')
    if float(metadata['format']['duration']) < record['cut_start_frame']/30+duration: raise RuntimeError('Raw recording ended early')
    if record['cut_duration_frames']!=duration*30: raise RuntimeError('Unexpected cut length')
    record.update({'raw':str(raw),'probe':metadata,'errors':errors,'client_exit':0})
    clips.append(record)
final=root/'output/决赛修订材料/回响版A10/檐下千秋_两分钟实机节选.mp4'
metadata=probe(final)
video=next(s for s in metadata['streams'] if s['codec_type']=='video')
audio=next(s for s in metadata['streams'] if s['codec_type']=='audio')
assert [video['width'],video['height']]==[1920,1080] and video['codec_name']=='h264' and audio['codec_name']=='aac'
assert abs(float(metadata['format']['duration'])-120)<.01
package=work/'unpacked'/Path(original['archive']).stem
assert base.sha256_file(package/'檐下千秋.exe')==original['exe_sha256']
assert base.sha256_file(original['archive'])==original['archive_sha256']
original.pop('error',None)
original.update({'passed':True,'file':str(final),'sha256':base.sha256_file(final),'probe':metadata,'clips':clips,
                 'exe_bytes_unchanged':True,'recovery':'Existing terminal recordings and final MP4 rechecked with explicit UTF-8 metadata decoding; no recapture'})
(evidence/'result.json').write_text(json.dumps(original,ensure_ascii=False,indent=2),encoding='utf-8')
sys.stdout.reconfigure(encoding='utf-8')
print(json.dumps({'passed':True,'file':str(final),'sha256':original['sha256'],'duration':metadata['format']['duration'],'native':[video['width'],video['height']]},ensure_ascii=False))
