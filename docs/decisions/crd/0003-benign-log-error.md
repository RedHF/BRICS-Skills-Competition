# CRD 0003：更正 T-02 的 DoD 第 5 条（「日志不含 ERROR:」在本机不可能通过）

- 编号：0003
- 日期：2026-09-28
- 类型：**更正**（不是变更；不移动范围、不加工作）
- 提出人：PM（自己在真机验证时发现）

## 谁提出的

PM。T-02 的真机验证跑的是解压后的真实 `檐下千秋.exe`，用 `release_smoke.gd` 做冒烟测试。

## 他们要什么

T-02 的 DoD 第 5 条里的一小句原文：

> - 日志里有 `PASS EXPORTED`，且不含 `ERROR:`；

问题：后半句在本机不可能通过。日志里**有且只有一行** `ERROR:`：

```text
ERROR: Failed to read the root certificate store.
   at: get_system_ca_certificates (platform/windows/os_windows.cpp:2558)
```

这是 Godot 读系统根证书存储失败，本机的已知环境问题：`LLM-tmp/2026-09-28-横屏与入口更新.md` 第 21 行原文写着「环境存在系统根证书读取提示与旧描摹细线抗锯齿警告；本地 HTTP 服务与测试流程可正常完成」。它与本次改动无关，客户端也修不了它。

同一次运行里，第 5 条的**其余每一小段都通过了**：ZIP 解压、`SHA256.txt` 逐行核对、发行目录体检干净、客户端自己拉起配套服务、`/healthz` 报 `content_version == 10`、客户端退出码 `0`、8090 端口随之释放、日志里有 `PASS EXPORTED`。

## 为什么

不改的话，T-02 会挂一条永远过不了的检查。执行的人只剩两个选择：默默跳过它，或者把「没做到」写成「做到了」。两者都比留下一条已知噪声更糟。

## 影响到什么

- `docs/tasks/README.md`：T-02 的 DoD 第 5 条，旁边加一句更正（原句保留）
- 涉及 `LLM-tmp/联调脚本/verify_release.py` 的日志判定；该文件属于 T-01，改动随 T-01 的缺陷修复一起提交
- 不涉及任何游戏源码、里程碑 DoD 或其他任务行

## 代价

无。检查仍然存在，只是把它对准它本来要防的东西。

## 决定

**accepted**，由 PM 决定。这不是范围变更，是一条不可能通过的检查的更正。

采用的说法：**把「不含 ERROR:」收窄成「除本机已知的环境提示外，不含任何 ERROR:」**。

- 已知提示只有一条，写成显式常量：`ERROR: Failed to read the root certificate store.`
- 其余任何 `ERROR:` 仍然判失败——收窄的是噪声，不是检查本身
- 判定逻辑抽成纯函数 `log_findings(log)`，由单元测试覆盖：干净日志、只含已知提示、含另一条 ERROR，三种情形各一条用例

## 新增的 DoD 条目

无。本条只更正一条不可能通过的检查，不加工作。

## Applied

- `docs/tasks/README.md`：v5（2026-09-28，`Corrections` 一节新增第三条，原句保留）
- `LLM-tmp/联调脚本/verify_release.py` 与 `test_release_tools.py`：随 T-01 的缺陷修复提交
