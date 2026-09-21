from pathlib import Path
import hashlib
import json
import os
import shutil
import socket
import subprocess
import tempfile
import zipfile

root = Path(__file__).resolve().parents[3]
package = root / "dist/檐下千秋-v10-可玩性修复版-20260915"
shutil.copy2(root / "LLM-tmp/服务端/content/chapters.json", package / "server/content/chapters.json")
shutil.copy2(Path("C:/Program Files/Go/LICENSE"), package / "LICENSE-Go.txt")
(package / "运行说明.txt").write_text("""《檐下千秋》可玩性修复版 2026-09-15（内容协议 v10）
完整解压后运行“檐下千秋.exe”。保留 server 文件夹；无需安装 Godot 或 Go。
游戏自动启动本机配套服务；退出游戏后自动关闭。运行前请退出旧版游戏。
存档位于 %APPDATA%/Godot/app_userdata/檐下千秋/save.json，兼容 v10 进度。

修复：主回车和小键盘回车调查、调查中切换设置等页面后的现场恢复、剧情回顾背景。
移动：WASD / 方向键；调查：空格 / 回车 / 小键盘回车，或点击调查点。
战斗：1 挥墨、2 斗拱、3 藻井、4 飞檐、5 闪身，支持数字小键盘及鼠标按钮。
对话：点击 / 空格 / 回车继续，左方向键回看上一句，Esc 返回。
设置：音量、静音、切换全屏。五章十任务；三种终章回应均有效。

测试覆盖范围与说明见源码 LLM-tmp/验证记录/2026-09-15-可玩性/README.md。
本包不附带玩家存档。许可证和 SHA256 校验文件随包提供。
""", encoding="utf-8-sig")
files = sorted(p for p in package.rglob("*") if p.is_file() and p.name != "SHA256.txt")
hashes = [f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(package).as_posix()}" for p in files]
(package / "SHA256.txt").write_text("\n".join(hashes)+"\n", encoding="utf-8")
archive = package.with_suffix(".zip")
with zipfile.ZipFile(archive,"w",zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    for path in sorted(package.rglob("*")):
        if path.is_file(): z.write(path,path.relative_to(package.parent))
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    for line in hashes:
        digest, relative = line.split("  ",1)
        assert hashlib.sha256(z.read(package.name+"/"+relative)).hexdigest() == digest
    review = Path(tempfile.mkdtemp(prefix="yanxia-qa-release-"))
    z.extractall(review)
with socket.socket() as probe:
    assert probe.connect_ex(("127.0.0.1",8090)) != 0, "Default port in use; preserve existing game"
env = os.environ.copy()
env["APPDATA"] = str(review / "appdata")
log = review / "release.log"
with log.open("w",encoding="utf-8") as output:
    proc = subprocess.Popen([str(review/package.name/"檐下千秋.exe"),"--headless","--audio-driver","Dummy","--script",str(root/"LLM-tmp/客户端/tests/release_smoke.gd")],env=env,cwd=review,stdout=output,stderr=output,creationflags=subprocess.CREATE_NO_WINDOW)
    try: code = proc.wait(timeout=65)
    finally:
        if proc.poll() is None:
            proc.terminate()
            proc.wait(timeout=5)
text = log.read_text(encoding="utf-8")
assert code == 0 and "PASS EXPORTED v10" in text and "ERROR:" not in text and "leaked" not in text, text
with socket.socket() as probe:
    assert probe.connect_ex(("127.0.0.1",8090)) != 0, "Companion server did not close"
result = {"archive":str(archive),"bytes":archive.stat().st_size,"sha256":hashlib.sha256(archive.read_bytes()).hexdigest(),"exported_smoke":"passed","auto_start_shutdown":"passed","isolated_review":str(review)}
(Path(__file__).parent/"release-verification.json").write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
print(text)
print(json.dumps(result,ensure_ascii=False))
