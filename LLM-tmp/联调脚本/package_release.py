"""组装、打包并自检一个《檐下千秋》Windows 发行目录。只用 Python 标准库。

用法示例：

    python "LLM-tmp/联调脚本/package_release.py" --version v11 --edition 横屏水墨版 \\
        --date 20260928 --build --notes-file "LLM-tmp/验证记录/2026-09-28-v11/运行说明-本版内容.txt"

    python "LLM-tmp/联调脚本/package_release.py" --dry-run

缺省值指向改动前就有的 v10 目标（`檐下千秋-v10-Windows-x64-20260914`），保证旧用法不变。
要覆盖一个已经存在的 ZIP，必须显式加 `--force`。
"""
from __future__ import annotations

import argparse
import hashlib
import os
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

DEFAULT_VERSION = 'v10'
DEFAULT_EDITION = 'Windows-x64'
DEFAULT_DATE = '20260914'
TITLE = '檐下千秋'
RELEASE_ROOT_NAME = 'dist'

RUNTIME_FILES = (
    f'{TITLE}.exe',
    'server/yanxia-server.exe',
    'server/content/chapters.json',
)
SHIPPED_FILES = (
    '运行说明.txt',
    'LICENSE-Go.txt',
    'LICENSE-Godot.txt',
    'COPYRIGHT-Godot.json',
)
MANIFEST_FILE = 'SHA256.txt'

# 发行包里不该出现的东西：本机存档、本机设置和任何测试脚本。
FORBIDDEN_NAMES = ('save.json', 'client.cfg', 'settings.cfg')
FORBIDDEN_SUFFIXES = ('.gd', '.uid', '.ps1', '.bat', '.cmd', '.pdb')

GODOT_CONSOLE = '.tools/godot/Godot_v4.5.2-stable_win64_console.exe'
CLIENT_PROJECT = 'LLM-tmp/客户端'
SERVER_PROJECT = 'LLM-tmp/服务端'
SERVER_CONTENT = 'LLM-tmp/服务端/content/chapters.json'
EXPORT_PRESET = 'Windows Desktop'
LICENSE_EXPORTER = 'LLM-tmp/验证记录/2026-09-15-可玩性/补充原始记录/export_licenses.gd'
LICENSE_GO_CANDIDATES = (
    'C:/Program Files/Go/LICENSE',
    'output/参赛材料/本科组_Track1_第二队/Task03/Final/'
    'Track01_Task03_第二队_檐下千秋_核心可玩实体/Windows-x64/LICENSE-Go.txt',
)

RUNBOOK_TEMPLATE = '''《檐下千秋》{version} · Windows x64
构建日期：{date}

完整解压后双击“檐下千秋.exe”。无需安装 Godot 或 Go，无需联网，也不用注册或登录。
请保留整个文件夹结构，不要只复制 EXE，也不要同时打开多个版本。
游戏会自动启动同目录 server 文件夹里的配套服务，退出后自动关闭。
运行前请先退出旧版游戏和旧版服务。

操作：
- 鼠标点击推进对话；空格或回车也可以。
- 调查与修复用鼠标描摹；战斗用数字键 1-5（数字小键盘同样有效），也可以点按钮。
- 设置里可以调音量、静音，并切换全屏。

存档：%APPDATA%\\Godot\\app_userdata\\{title}\\save.json
故障日志在同一目录下的 server.log 和 logs\\godot.log。
配套服务只监听本机 127.0.0.1:8090。

SHA256.txt 用于核对包内文件；第三方运行时许可随包附带。
{notes}'''


# ---------------------------------------------------------------- 纯逻辑

def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path) -> str:
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def manifest_line(digest: str, relative: str) -> str:
    """`SHA256.txt` 的一行。两个空格是 sha256sum 的格式，改成一个就再也对不上。"""
    return f'{digest}  {relative}'


def parse_manifest_line(line: str):
    digest, relative = line.split('  ', 1)
    return digest, relative


def release_names(version: str = DEFAULT_VERSION,
                  edition: str = DEFAULT_EDITION,
                  date: str = DEFAULT_DATE) -> dict:
    """发行版本名 → 目录名、ZIP 名与校验文件名。"""
    stem = f'{TITLE}-{version}-{edition}-{date}'
    return {'stem': stem, 'folder': stem, 'zip': f'{stem}.zip', 'checksum': f'{stem}.zip.sha256'}


def expected_entries():
    """发行目录里应当有且只有这 8 项。"""
    return tuple(sorted(RUNTIME_FILES + SHIPPED_FILES + (MANIFEST_FILE,)))


def build_manifest(folder, skip=(MANIFEST_FILE,)) -> list:
    """按相对路径排序的 `[{'path','bytes','sha256'}, ...]`，跳过清单自己。"""
    folder = Path(folder)
    skip = set(skip)
    entries = []
    for path in sorted(p for p in folder.rglob('*') if p.is_file()):
        relative = path.relative_to(folder).as_posix()
        if relative in skip:
            continue
        entries.append({
            'path': relative,
            'bytes': path.stat().st_size,
            'sha256': sha256_file(path),
        })
    return entries


def is_forbidden(relative: str) -> bool:
    name = Path(relative).name
    return name in FORBIDDEN_NAMES or Path(relative).suffix.lower() in FORBIDDEN_SUFFIXES


def audit_release(folder) -> dict:
    """发行目录的体检报告：缺了什么、混进了什么、多了什么。"""
    folder = Path(folder)
    present = {p.relative_to(folder).as_posix() for p in folder.rglob('*') if p.is_file()}
    expected = set(expected_entries())
    return {
        'missing': sorted(expected - present),
        'forbidden': sorted(relative for relative in present if is_forbidden(relative)),
        'extra': sorted(relative for relative in present - expected if not is_forbidden(relative)),
    }


def target_paths(version: str = DEFAULT_VERSION,
                 edition: str = DEFAULT_EDITION,
                 date: str = DEFAULT_DATE) -> dict:
    names = release_names(version, edition, date)
    root = ROOT / RELEASE_ROOT_NAME
    return {
        'names': names,
        'folder': root / names['folder'],
        'zip': root / names['zip'],
        'checksum': root / names['checksum'],
    }


# ---------------------------------------------------------------- 组装

def run(command, env=None) -> None:
    print('+ ' + ' '.join(str(part) for part in command), flush=True)
    result = subprocess.run(command, cwd=ROOT, env=env)
    if result.returncode != 0:
        raise SystemExit(f'命令失败（退出码 {result.returncode}）：{command[0]}')


def build_server(folder: Path) -> None:
    exe = folder / 'server' / 'yanxia-server.exe'
    exe.parent.mkdir(parents=True, exist_ok=True)
    run(['go', '-C', SERVER_PROJECT, 'build', '-trimpath', '-ldflags', '-s -w',
         '-o', str(exe), './cmd/server'])


def build_client(folder: Path) -> None:
    run([str(ROOT / GODOT_CONSOLE), '--headless', '--path', CLIENT_PROJECT,
         '--export-release', EXPORT_PRESET, str(folder / f'{TITLE}.exe')])


def copy_content(folder: Path) -> None:
    target = folder / 'server' / 'content' / 'chapters.json'
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / SERVER_CONTENT, target)


def export_godot_licenses(folder: Path) -> None:
    """让引擎自己吐出它的许可证与版权清单，而不是从旧包里抄。"""
    env = os.environ.copy()
    env['QA_RELEASE_DIR'] = str(folder)
    run([str(ROOT / GODOT_CONSOLE), '--headless', '--path', CLIENT_PROJECT,
         '--script', str(ROOT / LICENSE_EXPORTER)], env=env)


def copy_go_license(folder: Path) -> Path:
    for candidate in LICENSE_GO_CANDIDATES:
        source = Path(candidate)
        if source.is_file():
            shutil.copy2(source, folder / 'LICENSE-Go.txt')
            return source
    raise SystemExit('找不到 Go 的 LICENSE，试过：' + ' | '.join(LICENSE_GO_CANDIDATES))


def write_runbook(folder: Path, version: str, date: str, notes_file=None) -> None:
    notes = ''
    if notes_file:
        notes = Path(notes_file).read_text(encoding='utf-8').strip() + '\n'
    text = RUNBOOK_TEMPLATE.format(version=version, date=date, title=TITLE, notes=notes)
    (folder / '运行说明.txt').write_text(text, encoding='utf-8-sig')


def write_manifest(folder: Path) -> list:
    entries = build_manifest(folder)
    body = ''.join(manifest_line(entry['sha256'], entry['path']) + '\n' for entry in entries)
    (folder / MANIFEST_FILE).write_text(body, encoding='utf-8')
    return entries


def write_zip(folder: Path, archive: Path) -> None:
    """先写 `.part` 再改名，中途失败不会留下一个看起来正常的 ZIP。"""
    pending = archive.with_name(archive.name + '.part')
    with zipfile.ZipFile(pending, 'w', zipfile.ZIP_DEFLATED, compresslevel=6,
                         allowZip64=True) as output:
        for path in sorted(p for p in folder.rglob('*') if p.is_file()):
            output.write(path, path.relative_to(folder.parent).as_posix())
    pending.replace(archive)


def verify_zip(folder: Path, archive: Path, entries: list) -> None:
    """ZIP 的 CRC 与逐文件哈希都要对得上，否则整包作废。"""
    with zipfile.ZipFile(archive) as output:
        broken = output.testzip()
        if broken is not None:
            raise RuntimeError('ZIP 的 CRC 检查失败：' + broken)
        for entry in entries:
            data = output.read(f'{folder.name}/{entry["path"]}')
            if len(data) != entry['bytes'] or sha256_bytes(data) != entry['sha256']:
                raise RuntimeError('ZIP 内容与清单不一致：' + entry['path'])


# ---------------------------------------------------------------- 入口

def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description='组装并打包一个《檐下千秋》Windows 发行目录。')
    parser.add_argument('--version', default=DEFAULT_VERSION,
                        help=f'发行版本名，例如 v11（缺省 {DEFAULT_VERSION}）')
    parser.add_argument('--edition', default=DEFAULT_EDITION,
                        help=f'版本后缀，例如 横屏水墨版（缺省 {DEFAULT_EDITION}）')
    parser.add_argument('--date', default=DEFAULT_DATE,
                        help=f'构建日期 YYYYMMDD（缺省 {DEFAULT_DATE}）')
    parser.add_argument('--notes-file', default=None,
                        help='附加到“运行说明.txt”末尾的本版内容（UTF-8 纯文本）')
    parser.add_argument('--build', action='store_true',
                        help='先编译服务端并用 Godot 导出客户端，再打包')
    parser.add_argument('--force', action='store_true',
                        help='允许覆盖已经存在的 ZIP')
    parser.add_argument('--dry-run', action='store_true',
                        help='只打印目标路径，不写任何文件')
    return parser.parse_args(argv)


def main(argv=None) -> int:
    args = parse_args(argv)
    paths = target_paths(args.version, args.edition, args.date)
    folder, archive = paths['folder'], paths['zip']

    if args.dry_run:
        print(f'发行目录：{folder}')
        print(f'ZIP：     {archive}')
        print(f'校验文件：{paths["checksum"]}')
        if args.notes_file:
            print(f'运行说明附加内容：{args.notes_file}')
        return 0

    if archive.exists() and not args.force:
        raise SystemExit(f'{archive} 已存在；确认要覆盖请加 --force')

    folder.mkdir(parents=True, exist_ok=True)
    if args.build:
        build_server(folder)
        build_client(folder)
    copy_content(folder)
    export_godot_licenses(folder)
    copy_go_license(folder)
    write_runbook(folder, args.version, args.date, args.notes_file)

    report = audit_release(folder)
    if any(report.values()):
        raise SystemExit(
            f'发行目录不合格 {folder}\n'
            f'  缺少：{report["missing"]}\n'
            f'  不该有：{report["forbidden"]}\n'
            f'  多出来：{report["extra"]}')

    entries = write_manifest(folder)
    print(f'打包 {len(entries) + 1} 个文件……', flush=True)
    write_zip(folder, archive)
    print('检查 ZIP 的 CRC 与清单里的每个哈希……', flush=True)
    verify_zip(folder, archive, entries)

    digest = sha256_file(archive)
    paths['checksum'].write_text(f'{digest}  {archive.name}\n', encoding='utf-8')
    print(f'PASS ZIP integrity, {len(entries) + 1} entries, {archive.stat().st_size} bytes')
    print(f'PASS sha256 {digest}')
    print(archive)
    return 0


if __name__ == '__main__':
    sys.exit(main())
