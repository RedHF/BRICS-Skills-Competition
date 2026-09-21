"""Package already-built v10 binaries, verify ZIP entries and write SHA256 checksums."""
from pathlib import Path
import hashlib
import shutil
import zipfile

root = Path(__file__).resolve().parents[2]
folder = root / 'dist/檐下千秋-v10-Windows-x64-20260914'
assert (folder / '檐下千秋.exe').is_file()
assert (folder / 'server/yanxia-server.exe').is_file()
(folder / 'server/content').mkdir(parents=True, exist_ok=True)
shutil.copy2(root/'LLM-tmp/服务端/content/chapters.json', folder/'server/content/chapters.json')
for name in ['LICENSE-Godot.txt', 'COPYRIGHT-Godot.txt']:
    shutil.copy2(root/'LLM-tmp/交付/檐下千秋-功能修复版'/name, folder/name)
shutil.copy2(Path('C:/Program Files/Go/LICENSE'), folder/'LICENSE-Go.txt')
shutil.copy2(root/'LLM-tmp/2026-09-14-素材配音与首领更新.md', folder/'更新与素材记录.md')
(folder/'运行说明.txt').write_text('''《檐下千秋》v10 · Windows x64
构建日期：2026-09-14

完整解压后双击“檐下千秋.exe”。无需安装 Godot / Go，无需联网或登录。
请保留整个文件夹结构。游戏自动启动 server 内的配套服务，退出后自动关闭。
运行前退出旧版游戏和旧版服务。新客户端使用内容协议 v10。

新增：184 段配音、廊桥与社庙场景素材、透明白蚀精灵、第三技艺后的首领战。
戏楼“开台”获得第三项独立技艺“飞檐”后，清除游蚀，迎战“白蚀·噤声客”。
首领每 2.4 秒侵袭，三项技艺均需施展。失败后可回溯，零墨痕可免费回溯。

数字键 / 数字小键盘：
1 挥墨（普通攻击）
2 斗拱（护盾）
3 藻井（伤害与净化）
4 飞檐（攻击）
5 闪身（闪避下一次攻击）
未习得技艺暂不可用；也可点击战斗按钮。WASD / 方向键移动。
对白用鼠标、空格或回车继续；上一句、跳过、返回均停止上一句录音。
设置可调音量、静音及切换全屏。失败演出的“……”为静默。

存档：%APPDATA%\\Godot\\app_userdata\\檐下千秋\\save.json
沿用已有存档。本包不附带玩家存档或测试记录。
已完成开台的旧档不会强制回退或补打首领，首领随正常的新进度触发。
服务监听本机 127.0.0.1:8090；故障日志在同一存档目录 server.log 和 logs/godot.log。
不要单独复制 EXE 或同时打开多个版本。

图像筛选、AI 处理与本次变更见“更新与素材记录.md”。
SHA256.txt 用于核对包内文件。第三方运行时许可随包附带。
''', encoding='utf-8-sig')
files = sorted(p for p in folder.rglob('*') if p.is_file() and p.name != 'SHA256.txt')
assert all(p.name not in ['save.json','client.cfg','settings.cfg'] for p in files)
hashes = [f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(folder).as_posix()}' for p in files]
(folder/'SHA256.txt').write_text('\n'.join(hashes)+'\n', encoding='utf-8')
archive = folder.with_suffix('.zip')
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as z:
    for p in sorted(folder.rglob('*')):
        if p.is_file(): z.write(p,p.relative_to(folder.parent))
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    for entry in hashes:
        digest, relative = entry.split('  ',1)
        assert hashlib.sha256(z.read(folder.name+'/'+relative)).hexdigest() == digest
digest = hashlib.sha256(archive.read_bytes()).hexdigest()
archive.with_suffix('.zip.sha256').write_text(f'{digest}  {archive.name}\n',encoding='utf-8')
print(f'PASS ZIP integrity, {len(files)} file hashes; {archive.stat().st_size} bytes')
print(archive)
