"""Verify the actual exported echo EXE from a freshly unpacked preview ZIP."""
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

PORT = 8091


def port_free():
    with socket.socket() as probe:
        return probe.connect_ex(("127.0.0.1", PORT)) != 0


def clean_owned_server(server_exe):
    # Cleanup must never target an unrelated process just because it owns the
    # same port. Only this unique, newly unpacked executable is eligible.
    env = os.environ.copy()
    env["YANXIA_REVIEW_SERVER_EXE"] = str(server_exe)
    subprocess.run(["powershell", "-NoProfile", "-NonInteractive", "-Command",
                    "Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -eq $env:YANXIA_REVIEW_SERVER_EXE } | ForEach-Object { Stop-Process -Id $_.ProcessId }"],
                   env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                   creationflags=subprocess.CREATE_NO_WINDOW, timeout=15)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--archive")
    parser.add_argument("--archive-memory",choices=["yan_ping_an","she_cheng_xiang","she_ning_an","she_hui_chun"],default="she_ning_an")
    parser.add_argument("--visual", action="store_true")
    parser.add_argument("--full-journey", action="store_true")
    args = parser.parse_args()
    archives = list((base.ROOT / "dist").glob("*echo-v1*.zip"))
    archive = Path(args.archive).resolve() if args.archive else max(archives, key=lambda p:p.stat().st_mtime)
    if not port_free():
        raise RuntimeError("The echo port is in use; the verifier will not interrupt that service")
    stamp = datetime.now()
    work = base.ROOT / ".review" / "echo-export" / f"{stamp:%Y%m%d-%H%M%S-%f}"
    work.mkdir(parents=True)
    evidence = base.ROOT / "LLM-tmp" / "验证记录" / f"{stamp:%Y-%m-%d}-回响版" / f"{stamp:%H%M%S}-exported-client"
    evidence.mkdir(parents=True)
    with zipfile.ZipFile(archive) as source:
        if source.testzip(): raise RuntimeError("ZIP CRC check failed")
        source.extractall(work / "unpacked")
    package = work / "unpacked" / archive.stem
    audit = base.audit_release(package)
    if any(audit.values()): raise RuntimeError(f"Unexpected files in the exported preview: {audit}")
    result = {"kind":"exported-echo-client-check", "human_playtest":False,
              "archive":str(archive), "archive_sha256":base.sha256_file(archive),
              "manifest_lines_verified":check_manifest(package), "release_audit":audit,
              "edition_argument_used":False, "source_project_used":False, "passed":False}
    result["visual"] = args.visual
    result["offscreen_native_render"] = args.visual
    result["full_journey"] = args.full_journey
    env = os.environ.copy()
    env["APPDATA"] = str(work / "appdata")
    env["YANXIA_REVIEW_ARCHIVE"] = args.archive_memory
    result["archived_memory"] = args.archive_memory
    env["YANXIA_REVIEW_FULL"] = "1" if args.full_journey else "0"
    env["YANXIA_FIXTURE_PATH"] = str(package / "server/content/chapters.json")
    if args.visual:
        env["YANXIA_REVIEW_SHOTS"] = str(evidence / "frames")
        env["YANXIA_CAPTURE_SIZE"] = "1920x1080"
    else: env.pop("YANXIA_REVIEW_SHOTS", None)
    Path(env["APPDATA"]).mkdir()
    command = [str(package / "檐下千秋.exe"), "--verbose", "--audio-driver", "Dummy",
               "--script", str(base.ROOT / base.CLIENT_PROJECT / "tests/echo_smoke.gd"),
               "--log-file", str(evidence / "engine.log")]
    if args.visual:
        command += ["--rendering-driver", "opengl3_angle", "--position", "12000,12000", "--resolution", "1280x720"]
    else: command.append("--headless")
    server_exe = package / "server/yanxia-server.exe"
    process = None
    try:
        with (evidence / "console.log").open("w", encoding="utf-8") as log:
            process = subprocess.Popen(command, cwd=work, env=env, stdout=log,
                                       stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
            deadline = time.monotonic()+25
            while time.monotonic() < deadline and process.poll() is None:
                try:
                    with urllib.request.urlopen(f"http://127.0.0.1:{PORT}/healthz", timeout=1) as reply:
                        health = json.load(reply)
                    if health.get("edition") != "echo-v1" or health.get("content_version") != 10:
                        raise RuntimeError(f"Wrong companion service: {health}")
                    result["health"] = health
                    result["server_auto_started"] = True
                    break
                except OSError:
                    time.sleep(.1)
            if not result.get("server_auto_started"):
                raise RuntimeError("Exported client did not auto-start its echo companion")
            result["client_exit"] = process.wait(timeout=110)
        text = (evidence / "console.log").read_text(encoding="utf-8", errors="replace")
        result["errors"] = log_findings(text)
        if result["client_exit"] != 0 or "PASS echo client:" not in text or result["errors"]:
            raise RuntimeError("Exported client check failed; inspect console.log")
        if args.full_journey and "PASS full echo journey:" not in text:
            raise RuntimeError("Full journey did not reach its explicit completion check")
        deadline = time.monotonic()+5
        while not port_free() and time.monotonic() < deadline:
            time.sleep(.1)
        result["server_auto_stopped"] = port_free()
        if not result["server_auto_stopped"]:
            raise RuntimeError("Exported client left its companion running")
        saves = list((work / "appdata").rglob("echo-v1-save.json"))
        if len(saves) != 1: raise RuntimeError("Exported client did not use a separate echo save")
        saved = json.loads(saves[0].read_text(encoding="utf-8"))
        player = saved["players"][saved["local_player_id"]]
        result["saved_edition"] = saved.get("edition")
        result["completed_events"] = len(player["completed_events"])
        result["saved_capacity"] = player["capacity"]
        result["frames"] = sorted(p.name for p in (evidence / "frames").glob("*.png"))
        if args.visual:
            sizes = {}
            for path in (evidence / "frames").glob("*.png"):
                with path.open("rb") as image:
                    sizes[path.name] = list(struct.unpack(">II", image.read(24)[16:24]))
            result["frame_sizes"] = sizes
            if not sizes or any(size != [1920,1080] for size in sizes.values()):
                raise RuntimeError("Actual screenshot dimensions differ from the requested 1920x1080")
        expected_events, expected_capacity = (10,5) if args.full_journey else (4,4)
        if result["saved_edition"] != "echo-v1" or result["completed_events"] != expected_events or result["saved_capacity"] != expected_capacity:
            raise RuntimeError("Exported checkpoint does not match the verified chapter")
        result["passed"] = True
    except Exception as error:
        result["error"] = str(error)
    finally:
        if process is not None and process.poll() is None:
            subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                           creationflags=subprocess.CREATE_NO_WINDOW, timeout=15)
            process.wait(timeout=10)
        clean_owned_server(server_exe)
        (evidence / "result.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    raise SystemExit(main())
