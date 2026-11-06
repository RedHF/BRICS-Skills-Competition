"""Build an independent echo preview without touching selection submissions."""
from __future__ import annotations

import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import re
import subprocess
import sys

import package_release as base
from verify_release import log_findings


def run(command, log_path, *, cwd=base.ROOT, env=None):
    hidden = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
    with log_path.open("w", encoding="utf-8") as log:
        result = subprocess.run(command, cwd=cwd, env=env, stdout=log,
                                stderr=subprocess.STDOUT, creationflags=hidden, timeout=180)
    if result.returncode:
        raise RuntimeError(f"Build step failed; see {log_path}")
    if log_findings(log_path.read_text(encoding="utf-8",errors="replace")):
        raise RuntimeError(f"Build reported an error despite its exit code; see {log_path}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--tag", default="A-preview1")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_-]+", args.tag):
        parser.error("tag must contain letters, digits, underscores or hyphens")
    stamp = datetime.now()
    stem = f"檐下千秋-echo-v1-{args.tag}-{stamp:%Y%m%d}"
    folder = base.ROOT / "dist" / stem
    archive = folder.with_suffix(".zip")
    if folder.exists() or archive.exists():
        raise RuntimeError("This preview already exists; use a new tag to preserve its evidence")
    folder.mkdir(parents=True)
    evidence = base.ROOT / "LLM-tmp" / "验证记录" / f"{stamp:%Y-%m-%d}-回响版" / f"{stamp:%H%M%S}-package-{args.tag}"
    evidence.mkdir(parents=True)
    env = base.godot_environment()
    # Godot can exit 0 even if its temporary project.binary could not be
    # written. Give this build its own writable temp directory and audit logs.
    temporary = evidence / "temp"
    temporary.mkdir()
    env["TEMP"] = str(temporary)
    env["TMP"] = str(temporary)
    server = folder / "server" / "yanxia-server.exe"
    server.parent.mkdir()
    run(["go", "build", "-trimpath", "-ldflags", "-s -w", "-o", str(server), "./cmd/server"],
        evidence / "server-build.log", cwd=base.ROOT / base.SERVER_PROJECT)
    run([str(base.ROOT / base.GODOT_CONSOLE), "--headless", "--path", base.CLIENT_PROJECT,
         "--export-release", "Windows Echo", str(folder / "檐下千秋.exe")],
        evidence / "client-export.log", env=env)
    base.copy_content(folder)
    license_env = env.copy()
    license_env["QA_RELEASE_DIR"] = str(folder)
    run([str(base.ROOT / base.GODOT_CONSOLE), "--headless", "--path", base.CLIENT_PROJECT,
         "--script", str(base.ROOT / base.LICENSE_EXPORTER)], evidence / "licenses.log", env=license_env)
    base.copy_go_license(folder)
    base.copy_font_licenses(folder)
    instructions = """《檐下千秋》回响版 A · 预览验证

完整解压后双击“檐下千秋.exe”。无需安装 Godot 或 Go，无需联网。
保留同目录 server 文件夹；游戏自动启动配套服务，退出时关闭。

从主页选择“开始旅程”或“继续旅程”。
需要回看时使用“选择关卡”或“旅途收藏”。
归档确认使用纸墨谱页，可点击“再想想”或按 Esc 返回，确认后才保存取舍。

本版内容：
社庙重点改版：观察梁架与记号、选件转向接合、在檐下安放空碗、鼓纹三区拓显。
记录和手艺可以留下，鲜活共鸣按三→四→五格逐步展开。
取舍后亲手敲鼓，正常鼓声一直在，孩子跟拍由回春是否鲜活决定。
其余章节沿用原玩法，已适配新规则；不是全章节重新制作。

操作：
鼠标点击或拖动；木件可用 Tab 选择、回车安放，R 转半圈。
空碗也可用方向键移动、回车放下。
拓显可慢慢擦出，也可按住回车累计 1.5 秒完成当前区域；松开保留本次辅助进度。
守护使用数字键 1—5 或按钮，准备好后再开始。
设置可调音量、静音、全屏，并减弱环境动态与转场。

存档与版本：
本版内置 echo-v1 标识，使用独立回响版存档；不会覆盖原版旅程。
存档：%APPDATA%\\Godot\\app_userdata\\檐下千秋\\echo-v1-save.json
日志：同目录 echo-v1-server.log 与 logs\\godot.log
配套服务只监听本机 127.0.0.1:8091。请勿同时打开两个回响版窗口。

这是一份预览验证包，尚未完成真人体验、现场设备和最终材料验收。
自动流程检查不代表初次玩家能理解所有选择，也不能代替扬声器听感判断。
SHA256.txt 用于核对文件；第三方运行时许可随包保留。
"""
    (folder / "运行说明.txt").write_text(instructions, encoding="utf-8-sig")
    entries = base.write_manifest(folder)
    audit = base.audit_release(folder)
    if any(audit.values()):
        raise RuntimeError(f"Unexpected preview files: {audit}")
    base.write_zip(folder, archive)
    base.verify_zip(folder, archive, entries)
    digest = base.sha256_file(archive)
    archive.with_suffix(".zip.sha256").write_text(f"{digest}  {archive.name}\n", encoding="utf-8")
    result = {"kind":"echo-preview-build", "edition":"echo-v1", "tag":args.tag,
              "folder":str(folder), "archive":str(archive), "sha256":digest,
              "bytes":archive.stat().st_size, "files":entries, "human_playtest":False,
              "release_audit":audit, "export_preset":"Windows Echo", "artifact_integrity_passed":True,
              "runtime_verified":False}
    (evidence / "package.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({k:v for k,v in result.items() if k != "files"}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
