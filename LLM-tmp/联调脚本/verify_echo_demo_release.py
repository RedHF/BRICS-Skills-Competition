"""Exercise the embedded demo checkpoints in the real exported EXE."""
from __future__ import annotations
import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import socket
import struct
import subprocess
import sys
import time
import urllib.request
import zipfile
import package_release as base
from verify_release import check_manifest, log_findings
from verify_echo_release import clean_owned_server


def port_free():
    with socket.socket() as probe:
        return probe.connect_ex(("127.0.0.1",8092)) != 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--archive")
    parser.add_argument("--visual",action="store_true")
    args = parser.parse_args()
    archives = list((base.ROOT/"dist").glob("*echo-v1*.zip"))
    archive = Path(args.archive).resolve() if args.archive else max(archives,key=lambda p:p.stat().st_mtime)
    if not port_free(): raise RuntimeError("The demo port is busy; no existing service will be interrupted")
    stamp = datetime.now()
    work = base.ROOT/".review"/"echo-demo-export"/f"{stamp:%Y%m%d-%H%M%S-%f}"
    work.mkdir(parents=True)
    evidence = base.ROOT/"LLM-tmp"/"验证记录"/f"{stamp:%Y-%m-%d}-回响版"/f"{stamp:%H%M%S}-exported-demos"
    evidence.mkdir(parents=True)
    with zipfile.ZipFile(archive) as source:
        if source.testzip(): raise RuntimeError("ZIP CRC check failed")
        source.extractall(work/"unpacked")
    package = work/"unpacked"/archive.stem
    audit = base.audit_release(package)
    if any(audit.values()): raise RuntimeError(f"Unexpected package files: {audit}")
    env = os.environ.copy()
    env["APPDATA"] = str(work/"appdata")
    user = work/"appdata"/"Godot"/"app_userdata"/"檐下千秋"
    user.mkdir(parents=True)
    sentinels = {"echo-v1-save.json":b"normal-echo-progress-sentinel\n",
                 "save.json":b"original-progress-sentinel\n",
                 "settings.cfg":b"[audio]\nvolume=0.25\nmuted=false\n"}
    for name,data in sentinels.items(): (user/name).write_bytes(data)
    result = {"kind":"exported-demo-check","archive":str(archive),"archive_sha256":base.sha256_file(archive),
              "human_playtest":False,"source_project_used":False,"edition_argument_used":False,
              "manifest_lines_verified":check_manifest(package),"runs":[],"passed":False}
    server_exe = package/"server"/"yanxia-server.exe"
    process = None
    try:
        for index,mode in enumerate(["repair","choice","choice"]):
            label = f"{index+1}-{mode}"
            output = evidence/label
            output.mkdir()
            if args.visual: env["YANXIA_REVIEW_SHOTS"] = str(output/"frames")
            command = [str(package/"檐下千秋.exe"),"--verbose","--audio-driver","Dummy",
                       "--script",str(base.ROOT/base.CLIENT_PROJECT/"tests"/"echo_demo_smoke.gd"),
                       "--log-file",str(output/"engine.log")]
            if args.visual: command += ["--rendering-driver","opengl3_angle","--position","12000,12000","--resolution","1280x720"]
            else: command.append("--headless")
            command += ["--","--demo="+mode]
            with (output/"console.log").open("w",encoding="utf-8") as log:
                process = subprocess.Popen(command,cwd=work,env=env,stdout=log,stderr=subprocess.STDOUT,
                                           creationflags=subprocess.CREATE_NO_WINDOW)
                deadline = time.monotonic()+20
                health = None
                while process.poll() is None and time.monotonic()<deadline:
                    try:
                        with urllib.request.urlopen("http://127.0.0.1:8092/healthz",timeout=1) as reply:
                            health = json.load(reply)
                        break
                    except OSError: time.sleep(.1)
                if not health or health.get("edition") != "echo-v1": raise RuntimeError("Demo did not auto-start its companion")
                exit_code = process.wait(timeout=80)
            content = (output/"console.log").read_text(encoding="utf-8",errors="replace")
            errors = log_findings(content)
            if exit_code or errors or f"PASS exported demo: {mode}" not in content:
                raise RuntimeError(f"Demo failed: {label}; {errors}")
            deadline = time.monotonic()+5
            while not port_free() and time.monotonic()<deadline: time.sleep(.1)
            if not port_free(): raise RuntimeError("Demo companion was not closed")
            for name,data in sentinels.items():
                if (user/name).read_bytes()!=data: raise RuntimeError(f"Demo changed normal profile: {name}")
            profiles = list((user/"demo"/mode).glob("*/echo-v1-save.json"))
            expected_count = 1 if mode == "repair" else index
            if len(profiles)!=expected_count: raise RuntimeError("Reopening did not create a fresh demo profile")
            sizes = {}
            for path in (output/"frames").glob("*.png"):
                with path.open("rb") as image: sizes[path.name] = list(struct.unpack(">II",image.read(24)[16:24]))
            if args.visual and (not sizes or any(s!=([960,540] if n.endswith("-small.png") else [1920,1080]) for n,s in sizes.items())):
                raise RuntimeError("Demo render dimensions incorrect")
            result["runs"].append({"mode":mode,"client_exit":exit_code,"server_auto_started":True,
                                   "server_auto_stopped":True,"errors":errors,"normal_profiles_unchanged":True,
                                   "independent_profiles":len(profiles),"frame_sizes":sizes})
        result["passed"] = True
    except Exception as error:
        result["error"] = str(error)
    finally:
        if process is not None and process.poll() is None:
            subprocess.run(["taskkill","/PID",str(process.pid),"/T","/F"],stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL,creationflags=subprocess.CREATE_NO_WINDOW,timeout=15)
            process.wait(timeout=10)
        clean_owned_server(server_exe)
        (evidence/"result.json").write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding="utf-8")
    print(json.dumps(result,ensure_ascii=False,indent=2))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    raise SystemExit(main())
