"""在隔离目录里验证一个发行 ZIP：解压、核对哈希、启动真实的 EXE 跑冒烟测试，再收拾干净。

用法示例：

    python "LLM-tmp/联调脚本/verify_release.py" --version v11 --edition 横屏水墨版 --date 20260928
    python "LLM-tmp/联调脚本/verify_release.py" --dry-run

缺省值指向改动前就有的 v10 目标。验证结果写进 `LLM-tmp/验证记录/<日期>-<版本>/`。
隔离目录刻意建在工作区内：本机沙箱下，`tempfile.mkdtemp` 建的目录子进程写不进去。
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import socket
import subprocess
import sys
import time
import urllib.request
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import package_release as pr

PORT = 8090
SMOKE_SCRIPT = 'LLM-tmp/客户端/tests/release_smoke.gd'
SMOKE_PASS_TOKEN = 'PASS EXPORTED'
CONSOLE_LOG = 'console.log'
RESULT_FILE = 'release-verification.json'
BOOT_TIMEOUT = 25
EXIT_TIMEOUT = 45

# 本机已知、与改动无关的引擎环境提示。除它们之外，任何 ERROR: 都算失败。
# 见 docs/decisions/crd/0003-benign-log-error.md。
BENIGN_LOG_ERRORS = (
    'ERROR: Failed to read the root certificate store.',
)


def log_findings(log: str) -> list:
    """日志里真正的问题行：已知环境提示之外，任何 `ERROR:` 都算。"""
    return [line for line in log.splitlines()
            if 'ERROR:' in line
            and not any(benign in line for benign in BENIGN_LOG_ERRORS)]


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description='解压并真机验证一个发行 ZIP（缺省参数指向 v10）。')
    parser.add_argument('--version', default=pr.DEFAULT_VERSION,
                        help=f'发行版本名（缺省 {pr.DEFAULT_VERSION}）')
    parser.add_argument('--edition', default=pr.DEFAULT_EDITION,
                        help=f'版本后缀（缺省 {pr.DEFAULT_EDITION}）')
    parser.add_argument('--date', default=pr.DEFAULT_DATE,
                        help=f'构建日期 YYYYMMDD（缺省 {pr.DEFAULT_DATE}）')
    parser.add_argument('--content-version', type=int, default=10,
                        help='要求服务端 /healthz 报告的 content_version（缺省 10）')
    parser.add_argument('--result-dir', default=None,
                        help='验证结果目录（缺省 LLM-tmp/验证记录/<日期>-<版本>）')
    parser.add_argument('--keep', action='store_true',
                        help='保留隔离目录以便排查（缺省跑完就删）')
    parser.add_argument('--dry-run', action='store_true',
                        help='只打印将要验证的 ZIP 与结果目录，不做任何事')
    return parser.parse_args(argv)


def default_result_dir(version: str, date: str) -> Path:
    """验证结果的落点，例如 `LLM-tmp/验证记录/2026-09-28-v11/`。

    `--date` 是打包用的 `YYYYMMDD`，这里的目录名按仓库惯例带连字符。
    """
    stamp = date if '-' in date else f'{date[:4]}-{date[4:6]}-{date[6:]}'
    return pr.ROOT / 'LLM-tmp' / '验证记录' / f'{stamp}-{version}'


def isolated_root() -> Path:
    """在工作区内找一个空的隔离目录。"""
    base = pr.ROOT / 'LLM-tmp' / '联调脚本' / '.verify-tmp'
    base.mkdir(parents=True, exist_ok=True)
    for index in range(10000):
        candidate = base / f'run{index:04d}'
        try:
            candidate.mkdir()
        except FileExistsError:
            continue
        return candidate
    raise SystemExit('隔离目录用满了，先清掉：' + str(base))


def port_is_free(port: int = PORT) -> bool:
    with socket.socket() as probe:
        return probe.connect_ex(('127.0.0.1', port)) != 0


def check_manifest(package: Path) -> int:
    """逐行核对包内 SHA256.txt，返回核对过的行数。"""
    lines = (package / pr.MANIFEST_FILE).read_text(encoding='utf-8').splitlines()
    if not lines:
        raise RuntimeError('SHA256.txt 是空的')
    for line in lines:
        digest, relative = pr.parse_manifest_line(line)
        actual = pr.sha256_file(package / relative)
        if actual != digest:
            raise RuntimeError(f'SHA256 对不上：{relative}')
    return len(lines)


def wait_for_health(process, content_version: int):
    deadline = time.monotonic() + BOOT_TIMEOUT
    while time.monotonic() < deadline and process.poll() is None:
        try:
            with urllib.request.urlopen(f'http://127.0.0.1:{PORT}/healthz', timeout=1) as reply:
                health = json.load(reply)
            if health.get('content_version') == content_version:
                return health
            raise RuntimeError(f'内容协议不是 v{content_version}：{health}')
        except OSError:
            time.sleep(.2)
    raise RuntimeError('客户端没有在限时内拉起配套服务')


def main(argv=None) -> int:
    args = parse_args(argv)
    paths = pr.target_paths(args.version, args.edition, args.date)
    archive = paths['zip']
    result_dir = (Path(args.result_dir) if args.result_dir
                  else default_result_dir(args.version, args.date))

    if args.dry_run:
        print(f'要验证的 ZIP：{archive}')
        print(f'结果目录：    {result_dir}')
        return 0

    if not archive.is_file():
        raise SystemExit(f'找不到发行 ZIP：{archive}')
    if not port_is_free():
        raise SystemExit(f'端口 {PORT} 被占用；先退出正在运行的旧版游戏再验证。')

    review = isolated_root()
    log_path = review / CONSOLE_LOG
    print(f'隔离目录：{review}', flush=True)
    result = {
        'archive': str(archive),
        'archive_bytes': archive.stat().st_size,
        'archive_sha256': pr.sha256_file(archive),
        'content_version': args.content_version,
        'isolated_review': str(review),
    }
    try:
        with zipfile.ZipFile(archive) as source:
            source.extractall(review / 'unpacked')
        package = review / 'unpacked' / paths['names']['folder']
        if not package.is_dir():
            raise RuntimeError(f'ZIP 里没有发行目录 {paths["names"]["folder"]}')
        result['manifest_lines_verified'] = check_manifest(package)
        result['release_audit'] = pr.audit_release(package)
        if any(result['release_audit'].values()):
            raise RuntimeError(f'发行目录不合格：{result["release_audit"]}')

        env = os.environ.copy()
        env['APPDATA'] = str(review / 'appdata')
        command = [
            str(package / f'{pr.TITLE}.exe'), '--headless', '--verbose',
            '--audio-driver', 'Dummy', '--script', str(pr.ROOT / SMOKE_SCRIPT),
        ]
        print('+ ' + ' '.join(command), flush=True)
        with log_path.open('w', encoding='utf-8') as output:
            process = subprocess.Popen(command, cwd=review, env=env,
                                       stdout=output, stderr=output,
                                       creationflags=subprocess.CREATE_NO_WINDOW)
            try:
                result['health'] = wait_for_health(process, args.content_version)
                result['server_auto_started'] = True
                code = process.wait(timeout=EXIT_TIMEOUT)
            finally:
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=5)
        result['client_exit_code'] = code
        if code != 0:
            raise RuntimeError(f'客户端退出码是 {code}，不是 0')

        time.sleep(.3)
        if not port_is_free():
            raise RuntimeError('客户端自己拉起的配套服务没有随它退出')
        result['server_auto_stopped'] = True

        log = log_path.read_text(encoding='utf-8')
        if SMOKE_PASS_TOKEN not in log:
            raise RuntimeError(f'日志里没有 {SMOKE_PASS_TOKEN!r}：{log[-2000:]}')
        findings = log_findings(log)
        if findings:
            raise RuntimeError('日志里有 ERROR：\n' + '\n'.join(findings[:5]))
        result['exported_smoke'] = 'passed'

        result_dir.mkdir(parents=True, exist_ok=True)
        (result_dir / CONSOLE_LOG).write_text(log, encoding='utf-8')
        (result_dir / RESULT_FILE).write_text(
            json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        print(json.dumps(result, ensure_ascii=False, indent=2))
        print(f'PASS {archive.name}: 服务自动启停、内容协议 v{args.content_version}、'
              f'退出码 0、{result["manifest_lines_verified"]} 行哈希、冒烟测试通过')
        return 0
    finally:
        if args.keep:
            print(f'保留隔离目录：{review}')
        else:
            shutil.rmtree(review, ignore_errors=True)


if __name__ == '__main__':
    sys.exit(main())
