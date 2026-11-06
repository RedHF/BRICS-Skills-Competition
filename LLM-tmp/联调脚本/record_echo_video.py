"""Record two honest, labelled, automated UI excerpts from a fixed EXE."""
from __future__ import annotations
from datetime import datetime
import json,os,socket,subprocess,sys,zipfile
from pathlib import Path
import package_release as base
from verify_release import check_manifest,log_findings
from verify_echo_release import clean_owned_server

FFMPEG=Path('C:/Program Files/FFmpeg/ffmpeg.exe')
FFPROBE=FFMPEG.with_name('ffprobe.exe')

def probe(file):
    p=subprocess.run([str(FFPROBE),'-v','error','-show_streams','-show_format','-of','json',str(file)],capture_output=True,text=True,encoding='utf-8',errors='strict',check=True,creationflags=subprocess.CREATE_NO_WINDOW)
    return json.loads(p.stdout)

def main():
    with socket.socket() as connection:
        if connection.connect_ex(('127.0.0.1',8092))==0: raise RuntimeError('An existing demo is running; it will not be interrupted')
    archive=max((base.ROOT/'dist').glob('*echo-v1*.zip'),key=lambda p:p.stat().st_mtime)
    stamp=datetime.now()
    work=base.ROOT/'.review/echo-movie'/f'{stamp:%Y%m%d-%H%M%S}'
    work.mkdir(parents=True)
    evidence=base.ROOT/'LLM-tmp/验证记录'/f'{stamp:%Y-%m-%d}-回响版'/f'{stamp:%H%M%S}-recorded-excerpts'
    evidence.mkdir(parents=True)
    with zipfile.ZipFile(archive) as source:
        if source.testzip(): raise RuntimeError('ZIP CRC check failed')
        source.extractall(work/'unpacked')
    package=work/'unpacked'/archive.stem
    audit=base.audit_release(package)
    if any(audit.values()): raise RuntimeError(f'Unexpected package content: {audit}')
    manifest_count=check_manifest(package)
    exe=package/'檐下千秋.exe'
    exe_hash=base.sha256_file(exe)
    rendering='[display]\nwindow/size/viewport_width=1920\nwindow/size/viewport_height=1080\nwindow/size/window_width_override=1280\nwindow/size/window_height_override=720\nwindow/stretch/mode="viewport"\n'
    # This private rendering override changes output dimensions only. It is
    # neither shipped as a game change nor described as an unmodified folder.
    (package/'override.cfg').write_text(rendering,encoding='utf-8')
    env=os.environ.copy();env['APPDATA']=str(work/'appdata')
    records=[]
    result={'kind':'recorded-exported-excerpts','archive':str(archive),'archive_sha256':base.sha256_file(archive),
            'human_playtest':False,'input':'automated UI actions','source_project_used':False,
            'rendering_override':rendering,'manifest_lines_before_override':manifest_count,'exe_sha256':exe_hash,'passed':False}
    process=None
    try:
        for mode in ['repair','choice']:
            output=evidence/mode;output.mkdir()
            raw=work/f'{mode}.avi'
            env['YANXIA_MOVIE_RECORD']=str(output/'frames.json')
            command=[str(exe),'--verbose','--rendering-driver','opengl3_angle','--position','12000,12000',
                     '--write-movie',str(raw),'--fixed-fps','30','--disable-vsync','--log-file',str(output/'engine.log'),
                     '--script',str(base.ROOT/base.CLIENT_PROJECT/'tests/echo_movie_director.gd'),'--','--demo='+mode]
            with (output/'console.log').open('w',encoding='utf-8') as log:
                process=subprocess.Popen(command,cwd=work,env=env,stdout=log,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
                exit_code=process.wait(timeout=240)
            content=(output/'console.log').read_text(encoding='utf-8',errors='replace')
            errors=log_findings(content)
            if exit_code or errors or f'PASS exported movie: {mode}' not in content:
                raise RuntimeError(f'Recording failed: {mode}; {errors}')
            record=json.loads((output/'frames.json').read_text(encoding='utf-8'))
            metadata=probe(raw)
            video=next(s for s in metadata['streams'] if s['codec_type']=='video')
            if [video['width'],video['height']] != [1920,1080]: raise RuntimeError('Movie writer did not record native 1080')
            if not any(s['codec_type']=='audio' for s in metadata['streams']): raise RuntimeError('Recorded audio is missing')
            record.update({'raw':str(raw),'probe':metadata,'errors':errors,'client_exit':exit_code})
            records.append(record)
            clean_owned_server(package/'server/yanxia-server.exe')
            print(f'Recorded {mode}: native 1920x1080 with audio',flush=True)
        filters=[]
        for i,record in enumerate(records):
            first=record['cut_start_frame'];count=record['cut_duration_frames']
            filters.append(f'[{i}:v]trim=start_frame={first}:end_frame={first+count},setpts=PTS-STARTPTS[v{i}]')
            filters.append(f'[{i}:a]atrim=start={first/30:.8f}:duration={count/30:.8f},asetpts=PTS-STARTPTS[a{i}]')
        filters.append('[v0][a0][v1][a1]concat=n=2:v=1:a=1[v][a]')
        destination=base.ROOT/'output/决赛修订材料/回响版A11'
        destination.mkdir(parents=True,exist_ok=True)
        final=destination/'檐下千秋_两分钟实机节选.mp4'
        if final.exists(): raise RuntimeError('The final video already exists; preserve it and choose a new revision')
        command=[str(FFMPEG),'-hide_banner','-i',records[0]['raw'],'-i',records[1]['raw'],'-filter_complex',';'.join(filters),
                 '-map','[v]','-map','[a]','-c:v','libx264','-preset','medium','-crf','18','-pix_fmt','yuv420p',
                 '-c:a','aac','-b:a','192k','-movflags','+faststart','-map_metadata','-1',str(final)]
        with (evidence/'encode.log').open('w',encoding='utf-8') as log:
            subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=240,creationflags=subprocess.CREATE_NO_WINDOW)
        metadata=probe(final)
        video=next(s for s in metadata['streams'] if s['codec_type']=='video')
        if [video['width'],video['height']]!=[1920,1080] or abs(float(metadata['format']['duration'])-120)>.1:
            raise RuntimeError('Final video dimensions or duration are incorrect')
        result.update({'passed':True,'file':str(final),'sha256':base.sha256_file(final),'probe':metadata,
                       'exe_bytes_unchanged':base.sha256_file(exe)==exe_hash,'clips':records})
        if not result['exe_bytes_unchanged']: raise RuntimeError('Recording changed the exported EXE')
    except Exception as error:
        result['error']=str(error);result['passed']=False
    finally:
        if process is not None and process.poll() is None:
            subprocess.run(['taskkill','/PID',str(process.pid),'/T','/F'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,creationflags=subprocess.CREATE_NO_WINDOW,timeout=15)
            process.wait(timeout=10)
        clean_owned_server(package/'server/yanxia-server.exe')
        (evidence/'result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k not in ['probe','clips','rendering_override']},ensure_ascii=False,indent=2))
    return 0 if result['passed'] else 1

if __name__=='__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    raise SystemExit(main())
