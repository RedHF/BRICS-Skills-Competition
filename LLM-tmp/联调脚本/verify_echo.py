"""Exercise the echo client against a fresh, isolated local save and capture it."""

from __future__ import annotations

import argparse
from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
import socket
import struct
import subprocess
import sys
import time
import urllib.request
from verify_release import log_findings


def run() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--visual", action="store_true")
    parser.add_argument("--width", type=int, default=1280)
    parser.add_argument("--height", type=int, default=720)
    parser.add_argument("--label", default="smoke")
    parser.add_argument("--archive", choices=["yan_ping_an", "she_cheng_xiang", "she_ning_an", "she_hui_chun"], default="she_ning_an")
    parser.add_argument("--original-check", action="store_true", help="run the original-edition resource and UI regression")
    parser.add_argument("--full-journey", action="store_true", help="also check the remaining six echo event UI flows")
    parser.add_argument("--capture-demo-seeds", action="store_true", help="capture actual isolated checkpoints for the two embedded demo entries")
    args = parser.parse_args()
    if args.original_check and args.full_journey:
        parser.error("choose either the original regression or the full echo journey")
    edition = "original" if args.original_check else "echo-v1"
    if args.width < 960 or args.height < 540:
        parser.error("use a supported window size (at least 960 by 540)")
    if not args.label.replace("-", "").replace("_", "").isalnum():
        parser.error("label must contain letters, digits, underscores or hyphens")

    root = Path(__file__).resolve().parents[2]
    now = datetime.now(timezone(timedelta(hours=8)))
    identifier = f"{now:%H%M%S-%f}-{args.label}"
    work = root / ".review" / "echo-v1" / identifier
    output = root / "LLM-tmp" / "验证记录" / f"{now:%Y-%m-%d}-回响版" / identifier
    work.mkdir(parents=True)
    output.mkdir(parents=True)
    binary = work / "yanxia-server.exe"
    hidden = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
    with (output / "build.log").open("w", encoding="utf-8") as log:
        subprocess.run(
            ["go", "build", "-o", str(binary), "./cmd/server"],
            cwd=root / "LLM-tmp" / "服务端", stdout=log,
            stderr=subprocess.STDOUT, check=True, timeout=60,
            creationflags=hidden,
        )
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    url = f"http://127.0.0.1:{port}"
    command = [
        str(binary), "-edition", edition, "-addr", f"127.0.0.1:{port}",
        "-content", str(root / "LLM-tmp" / "服务端" / "content" / "chapters.json"),
        "-data", str(work / "save.json"),
    ]
    result = {"kind": "automated-client-check", "human_playtest": False,
              "size": [args.width, args.height], "visual": args.visual, "edition": edition,
              "archived": None if args.original_check else args.archive,
              "full_journey": args.full_journey,
              "offscreen_native_render": args.visual and not args.original_check,
              "output": str(output), "passed": False}
    with (output / "server.log").open("w", encoding="utf-8") as server_log:
        server = subprocess.Popen(command, cwd=root, stdout=server_log,
                                  stderr=subprocess.STDOUT, creationflags=hidden)
        try:
            ready = False
            for _ in range(60):
                if server.poll() is not None:
                    raise RuntimeError("isolated test service stopped before readiness")
                try:
                    with urllib.request.urlopen(url + "/healthz", timeout=1) as response:
                        health = json.load(response)
                    if health.get("edition") != edition:
                        raise RuntimeError("port does not belong to the echo test service")
                    ready = True
                    break
                except OSError:
                    time.sleep(0.1)
            if not ready:
                raise RuntimeError("isolated service readiness timed out")
            env = os.environ.copy()
            env["APPDATA"] = str(work / "appdata")
            env["YANXIA_REVIEW_SHOTS"] = str(output / "frames")
            env["YANXIA_REVIEW_ARCHIVE"] = args.archive
            env["YANXIA_REVIEW_FULL"] = "1" if args.full_journey else "0"
            if args.capture_demo_seeds:
                env["YANXIA_DEMO_SAVE"] = str(work / "save.json")
                env["YANXIA_DEMO_CAPTURE"] = str(root / "LLM-tmp" / "客户端" / "assets" / "echo_v1" / "demo")
            if args.visual and not args.original_check:
                env["YANXIA_CAPTURE_SIZE"] = f"{args.width}x{args.height}"
            Path(env["APPDATA"]).mkdir()
            godot = root / ".tools" / "godot" / "Godot_v4.5.2-stable_win64_console.exe"
            client = [str(godot), "--path", str(root / "LLM-tmp" / "客户端")]
            if args.visual:
                client += ["--rendering-driver", "opengl3_angle", "--position", "12000,12000"]
            else:
                client += ["--headless"]
            client += ["--resolution", f"{args.width}x{args.height}", "--script",
                       "res://tests/release_smoke.gd" if args.original_check else "res://tests/echo_smoke.gd",
                       "--log-file", str(output / "engine.log"),
                       "--", "--edition=" + edition, "--server-url=" + url]
            with (output / "client.log").open("w", encoding="utf-8") as log:
                completed = subprocess.run(client, cwd=root, env=env, stdout=log,
                                           stderr=subprocess.STDOUT, timeout=170,
                                           creationflags=hidden)
            text = (output / "client.log").read_text(encoding="utf-8", errors="replace")
            result["client_exit"] = completed.returncode
            marker = "PASS EXPORTED current release:" if args.original_check else "PASS echo client:"
            result["passed"] = completed.returncode == 0 and marker in text
            if args.full_journey and "PASS full echo journey:" not in text:
                result["passed"] = False
            result["script_errors"] = [line for line in text.splitlines() if "SCRIPT ERROR" in line]
            result["errors"] = log_findings(text)
            result["frames"] = sorted(p.name for p in (output / "frames").glob("*.png"))
            result["frame_sizes"] = {}
            for path in (output / "frames").glob("*.png"):
                with path.open("rb") as image:
                    result["frame_sizes"][path.name] = list(struct.unpack(">II",image.read(24)[16:24]))
            if args.visual and not args.original_check:
                if not result["frames"] or any(size != [args.width,args.height] for size in result["frame_sizes"].values()):
                    result["passed"] = False
            if result["errors"]:
                result["passed"] = False
            if not result["passed"]:
                result["log_tail"] = text.splitlines()[-30:]
        finally:
            server.terminate()
            try:
                server.wait(timeout=10)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait(timeout=10)
    (output / "result.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    raise SystemExit(run())
