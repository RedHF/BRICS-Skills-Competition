"""Prove both real-export harnesses execute failing checks in release mode."""
from pathlib import Path
from datetime import datetime
import hashlib
import json
import os
import subprocess
import sys
import package_release as base

stamp = datetime.now()
# Select the expanded directory, not its ZIP/checksum siblings.
packages = [p for p in (base.ROOT/"dist").glob("*echo-v1-A-preview*-*") if p.is_dir()]
package = max(packages,key=lambda p:p.stat().st_mtime)
evidence = base.ROOT/"LLM-tmp"/"验证记录"/f"{stamp:%Y-%m-%d}-回响版"/f"{stamp:%H%M%S}-release-check-negative"
evidence.mkdir(parents=True)
env = os.environ.copy()
env["YANXIA_EXPECT_CHECK_FAILURE"] = "1"
env["APPDATA"] = str(evidence/"isolated-appdata")
result = {"kind":"release-check-negative-control","human_playtest":False,
          "archive_sha256":base.sha256_file(package.with_suffix(".zip")),"runs":[],"passed":False}
for name in ["echo_smoke.gd","echo_demo_smoke.gd"]:
    harness = base.ROOT/base.CLIENT_PROJECT/"tests"/name
    command = [str(package/"檐下千秋.exe"),"--headless","--audio-driver","Dummy","--script",str(harness),"--log-file",str(evidence/(name+".engine.log"))]
    completed = subprocess.run(command,cwd=evidence,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,
                               creationflags=subprocess.CREATE_NO_WINDOW,timeout=20)
    content = completed.stdout.decode("utf-8",errors="replace")
    (evidence/(name+".log")).write_text(content,encoding="utf-8")
    ok = completed.returncode==98 and "EXPECTED_RELEASE_CHECK_FAILURE" in content
    result["runs"].append({"harness":name,"sha256":hashlib.sha256(harness.read_bytes()).hexdigest(),"exit":completed.returncode,"failure_observed":ok})
result["passed"] = all(r["failure_observed"] for r in result["runs"])
(evidence/"result.json").write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding="utf-8")
sys.stdout.reconfigure(encoding="utf-8")
print(json.dumps(result,ensure_ascii=False,indent=2))
raise SystemExit(0 if result["passed"] else 1)
