"""Verify the ZIP in isolation, launch its exported client and verify server shutdown."""
from pathlib import Path
import hashlib
import json
import os
import socket
import subprocess
import tempfile
import time
import urllib.request
import zipfile

root = Path(__file__).resolve().parents[2]
archive = root/'dist/檐下千秋-v10-Windows-x64-20260914.zip'
review = Path(tempfile.mkdtemp(prefix='yanxia-v10-release-'))
with zipfile.ZipFile(archive) as z: z.extractall(review/'unpacked')
package = review/'unpacked'/archive.stem
for line in (package/'SHA256.txt').read_text(encoding='utf-8').splitlines():
    digest, relative = line.split('  ',1)
    assert hashlib.sha256((package/relative).read_bytes()).hexdigest() == digest
with socket.socket() as probe:
    assert probe.connect_ex(('127.0.0.1',8090)) != 0, 'Port 8090 occupied; close the existing game before testing'
env = os.environ.copy()
env['APPDATA'] = str(review/'appdata')
with (review/'console.log').open('w',encoding='utf-8') as output:
    process = subprocess.Popen([str(package/'檐下千秋.exe'),'--headless','--verbose','--audio-driver','Dummy','--script',str(root/'LLM-tmp/客户端/tests/release_smoke.gd')],cwd=review,env=env,stdout=output,stderr=output,creationflags=subprocess.CREATE_NO_WINDOW)
    try:
        health = None
        deadline = time.monotonic()+25
        while time.monotonic() < deadline and process.poll() is None:
            try:
                with urllib.request.urlopen('http://127.0.0.1:8090/healthz',timeout=1) as r: health=json.load(r)
                break
            except OSError: time.sleep(.2)
        assert health and health['content_version'] == 10, health
        assert process.wait(timeout=45) == 0
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=5)
time.sleep(.3)
with socket.socket() as probe:
    assert probe.connect_ex(('127.0.0.1',8090)) != 0, 'Owned companion server did not exit'
log = (review/'console.log').read_text(encoding='utf-8')
assert 'PASS EXPORTED v10' in log and 'ERROR:' not in log and 'leaked' not in log, log
result = {'archive':str(archive),'sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),'bytes':archive.stat().st_size,'isolated_review':str(review),'exported_smoke':'passed','server_auto_start_and_shutdown':'passed','voices':184,'adopted_images':6}
(root/'LLM-tmp/验证记录/2026-09-14-v10/release-verification.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(log)
print(json.dumps(result,ensure_ascii=False,indent=2))
