"""Capture labelled movement input from the newly exported game, isolated save."""
from datetime import datetime
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import zipfile
import package_release as base
from verify_release import check_manifest, log_findings
from verify_echo_release import clean_owned_server


def main():
    with socket.socket() as connection:
        if connection.connect_ex(("127.0.0.1",8091)) == 0:
            raise RuntimeError("An existing journey is running; it will not be interrupted")
    archive = base.ROOT / "dist/檐下千秋-echo-v1-A-preview12-20261104.zip"
    stamp = datetime.now()
    work = base.ROOT / ".review/echo-walk-movie" / f"{stamp:%Y%m%d-%H%M%S}"
    evidence = base.ROOT / "LLM-tmp/验证记录" / f"{stamp:%Y-%m-%d}-回响版" / f"{stamp:%H%M%S}-walking-movie"
    work.mkdir(parents=True)
    evidence.mkdir(parents=True)
    with zipfile.ZipFile(archive) as source:
        if source.testzip(): raise RuntimeError("ZIP CRC failure")
        source.extractall(work / "unpacked")
    package = work / "unpacked" / archive.stem
    manifest_count = check_manifest(package)
    exe = package / "檐下千秋.exe"
    exe_hash = base.sha256_file(exe)
    (package / "override.cfg").write_text('[display]\nwindow/size/viewport_width=1920\nwindow/size/viewport_height=1080\nwindow/size/window_width_override=1280\nwindow/size/window_height_override=720\nwindow/stretch/mode="viewport"\n',encoding="utf-8")
    env = os.environ.copy()
    env["APPDATA"] = str(work / "appdata")
    env["YANXIA_WALK_RECORD"] = str(evidence / "frames.json")
    raw = work / "walk.avi"
    command = [str(exe),"--rendering-driver","opengl3_angle","--position","12000,12000",
               "--write-movie",str(raw),"--fixed-fps","30","--disable-vsync",
               "--script",str(base.ROOT/base.CLIENT_PROJECT/"tests/echo_walk_movie.gd"),
               "--log-file",str(evidence/"engine.log")]
    process = None
    try:
        with (evidence/"console.log").open("w",encoding="utf-8") as log:
            process = subprocess.Popen(command,cwd=work,env=env,stdout=log,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
            code = process.wait(timeout=90)
        text = (evidence/"console.log").read_text(encoding="utf-8",errors="replace")
        if code or log_findings(text) or "PASS exported walking movie" not in text:
            raise RuntimeError("Walking recording failed; inspect console.log")
        record = json.loads((evidence/"frames.json").read_text(encoding="utf-8"))
        start = record["cut_start_frame"]
        destination = base.ROOT/"output/决赛修订材料/回响版A12"
        destination.mkdir(parents=True,exist_ok=True)
        final = destination/"A12_实机行走检查.mp4"
        if final.exists(): raise RuntimeError("Preserve existing recording")
        ffmpeg = Path("C:/Program Files/FFmpeg/ffmpeg.exe")
        vf = f"trim=start_frame={start}:end_frame={start+270},setpts=PTS-STARTPTS"
        af = f"atrim=start={start/30:.8f}:duration=9,asetpts=PTS-STARTPTS"
        subprocess.run([str(ffmpeg),"-v","error","-i",str(raw),"-vf",vf,"-af",af,
                        "-c:v","libx264","-preset","medium","-crf","18","-pix_fmt","yuv420p",
                        "-c:a","aac","-b:a","192k","-movflags","+faststart",str(final)],check=True,timeout=60,creationflags=subprocess.CREATE_NO_WINDOW)
        if base.sha256_file(exe) != exe_hash: raise RuntimeError("EXE bytes changed")
        result = {"passed":True,"human_playtest":False,"source_project_used":False,"native_movie_writer":True,
                  "private_viewport_override":True,"archive_sha256":base.sha256_file(archive),"exe_sha256":exe_hash,
                  "manifest_lines_before_override":manifest_count,"file":str(final),"sha256":base.sha256_file(final),"seconds":9}
        (evidence/"result.json").write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding="utf-8")
        print(json.dumps(result,ensure_ascii=False,indent=2))
    finally:
        if process and process.poll() is None:
            process.kill()
            process.wait(timeout=10)
        clean_owned_server(package/"server/yanxia-server.exe")


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
