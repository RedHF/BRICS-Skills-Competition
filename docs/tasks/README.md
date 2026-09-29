# 任务表

一个仓库一张表。本作业是**小作业**，没有架构师：里程碑 DoD、任务行和任务 DoD 都由 PM 写，**Verdicts** 行也由 PM 写。

- 作业：`release-v11`　分支：`crew/release-v11`　PRD：`docs/design/prd-2026-09-28-release-v11.md`
- 里程碑：M1（唯一一个）
- **Shape**：全部 `solo`。小作业没有架构师，而 `pair` 形状必须先有架构师钉死 import 路径、导出名、签名、返回值和错误行为这五项，所以本表没有 `pair` 行。

---

## 里程碑 M1：双击就能玩的新发行包

**目标（一句话）**：从当前源码做出一个解压即玩的 Windows x64 包，里面是 2026-09-28 的全部效果。

**用户怎么试**：解压 `dist/檐下千秋-v11-横屏水墨版-20260928.zip`，双击 `檐下千秋.exe`。

**里程碑 DoD**（用户能读、能自己判断，不含任何命令）

1. 双击 `檐下千秋.exe` 能进入新版欢迎页——1280×720 横屏、水墨背景；点「启程」能进关卡页，再进游戏。
2. 界面是水墨 UI 的三页结构：主页、关卡、游戏；主页上有「旅途收藏」，下面有记忆图录、取舍记录、往事回放。
3. 玩到有对白的桥段能听到新配音（184 段，Qwen 重制版），音量正常、不炸音。
4. 包里有「运行说明.txt」、`LICENSE-Go.txt`、`LICENSE-Godot.txt`、`COPYRIGHT-Godot.json` 和 `SHA256.txt`；`SHA256.txt` 里每一行都能对上解压出来的文件。
5. 旧的 `dist/檐下千秋-v10-可玩性修复版-20260915.zip` 原样还在；`dist/README.md` 说清楚哪个包是什么、哪个进 Git、哪个不进。
6. 仓库里不再有指向不存在文件的路径。

---

### T-01 让发行脚本按版本参数工作，并给纯逻辑加单元测试

- **Verdicts**：code: not run — 本会话没有 `crew_*` 角色工具（不是 crew 预设），没有独立代码评审角色，由 PM 自查，见 state.json 的 notes；security: skipped — 本次只把已存在的发行脚本参数化，不触及网络、登录、权限、密钥、用户输入，也没有新依赖；qa: not run — 没有独立 QA 角色，DoD 由 PM 用 unittest 与两个 `--dry-run` 直接核对，原始输出写在本次提交信息里；doc: not run — 没有独立文档评审角色
- **里程碑**：M1
- **Shape**：solo
- **拥有文件**：
  - `LLM-tmp/联调脚本/package_release.py`
  - `LLM-tmp/联调脚本/verify_release.py`
  - `LLM-tmp/联调脚本/test_release_tools.py`（新建）
- **测试文件**：`LLM-tmp/联调脚本/test_release_tools.py`（就在上面这份拥有文件清单里）
- **依赖**：无
- **DoD**
  1. 两个脚本不再写死 `v10`、`20260914`、`檐下千秋-v10-Windows-x64-20260914`。版本名和日期由命令行参数给出；**缺省值仍指向现有的 v10 包，保证旧用法不变**。
  2. 纯逻辑抽成可导入的函数——版本名到目录名与 ZIP 名的映射、发行目录必须包含的文件清单、`SHA256.txt` 每行的格式；`import` 这两个模块时不执行任何打包或写盘。
  3. 单元测试在改动**之前**是红的、改动**之后**是绿的。命令：
     `python -m unittest discover -s "LLM-tmp/联调脚本" -p "test_release_tools.py" -v`
  4. `package_release.py --help` 能打印用法；带 `--dry-run` 用缺省参数运行时，打印的目标路径仍是 v10 那一个，且不写任何文件。
  5. `go -C LLM-tmp/服务端 test ./...` 仍全绿（本次不碰 Go，跑一次确认没有误伤）。

### T-02 构建、组装并真机验证 v11 发行包

- **里程碑**：M1
- **Shape**：solo
- **拥有文件**（本任务**产出**的文件，不是源码）：
  - `dist/檐下千秋-v11-横屏水墨版-20260928/檐下千秋.exe`
  - `dist/檐下千秋-v11-横屏水墨版-20260928/server/yanxia-server.exe`
  - `dist/檐下千秋-v11-横屏水墨版-20260928/server/content/chapters.json`
  - `dist/檐下千秋-v11-横屏水墨版-20260928/运行说明.txt`
  - `dist/檐下千秋-v11-横屏水墨版-20260928/LICENSE-Go.txt`
  - `dist/檐下千秋-v11-横屏水墨版-20260928/LICENSE-Godot.txt`
  - `dist/檐下千秋-v11-横屏水墨版-20260928/COPYRIGHT-Godot.json`
  - `dist/檐下千秋-v11-横屏水墨版-20260928/SHA256.txt`
  - `dist/檐下千秋-v11-横屏水墨版-20260928.zip`
  - `dist/檐下千秋-v11-横屏水墨版-20260928.zip.sha256`
  - `LLM-tmp/验证记录/2026-09-28-v11/运行说明-本版内容.txt`
  - `LLM-tmp/验证记录/2026-09-28-v11/release-verification.json`
  - `LLM-tmp/验证记录/2026-09-28-v11/console.log`
  - 前八项是发行目录的内容，由打包脚本生成；`.zip` 与 `.zip.sha256` 由它打包并自检；验证脚本产出最后两项。
  - 这个文件清单必须逐行是一个路径，后面不跟任何说明文字：`pm-write-guard` 按行解析它来决定 PM 能不能写这个路径。
- **测试文件**：无。理由：本任务产出的是构建产物，并靠**真机运行**判定；没有可被单元测试覆盖的代码行为。替代它的是可重复执行的 `verify_release.py`，见 DoD 第 5 条。
- **依赖**：T-01（要跑它改好的脚本）
- **DoD**
  1. 服务端编译成功：`go -C LLM-tmp/服务端 build -trimpath -ldflags "-s -w" -o <发行目录>/server/yanxia-server.exe ./cmd/server`。
  2. 客户端用 4.5.2 release 模板导出成功、资源内嵌：`<发行目录>/檐下千秋.exe`。
  3. 发行目录里必须有且只有这 8 项：`檐下千秋.exe`、`server/yanxia-server.exe`、`server/content/chapters.json`（与 `LLM-tmp/服务端/content/chapters.json` 字节相同）、`运行说明.txt`、`LICENSE-Go.txt`、`LICENSE-Godot.txt`、`COPYRIGHT-Godot.json`、`SHA256.txt`。**不得含** `save.json`、`client.cfg`、`settings.cfg`，也不得含任何 `.gd`、`.ps1`、`.bat` 测试脚本。
  4. 打包脚本打印 `PASS ZIP integrity`：ZIP 的 CRC 检查通过，且 ZIP 内每个文件的哈希与 `SHA256.txt` 一致；ZIP 与 `.zip.sha256` 同时写出。
  5. **真机验证**：把 ZIP 解压到隔离临时目录，用隔离的 `APPDATA` 启动**真实的** `檐下千秋.exe`（`--headless --audio-driver Dummy --script res://tests/release_smoke.gd`），要求全部满足：
     - 客户端自己拉起同目录的服务端，`http://127.0.0.1:8090/healthz` 有应答且 `content_version == 10`；
     - 客户端进程退出码为 `0`；
     - 日志里有 `PASS EXPORTED`，且不含 `ERROR:`；
     - 退出后 8090 端口已释放（自己拉起的服务端确实关掉了）。
     命令：`python "LLM-tmp/联调脚本/verify_release.py" --version v11 --date 20260928`
  6. 验证结果写进 `LLM-tmp/验证记录/2026-09-28-v11/release-verification.json`，含 ZIP 的 SHA256、字节数、逐文件哈希结论。
  7. ZIP 小于 100 MiB（GitHub 单文件上限）；确认后**留在本地 `dist/`，不 `git add`**。

### T-03 更新发行记录与面向读者的说明

- **里程碑**：M1
- **Shape**：solo
- **拥有文件**：
  - `LLM-tmp/2026-09-28-v11发行记录.md`（新建）
  - `dist/README.md`
  - `LLM-tmp/启动客户端.md`
  - `README.md`（**只改「当前状态」段**）
- **测试文件**：无。理由：纯文档改动，没有可被单元测试覆盖的行为；核对方式是逐条对照 T-02 的真实数字。
- **依赖**：T-02（要写进真实的 SHA256、字节数和验证结论）
- **DoD**
  1. `LLM-tmp/2026-09-28-v11发行记录.md` 写清：发行版本号 v11 与内容协议 v10 的区别；包名、字节数与 ZIP SHA256；包里有什么、不包含什么；如何复现（构建命令与验证命令）；验证结论；以及本包之后仍然存在的已知限制。
  2. `dist/README.md` 说清三件事：v10 包在 Git 里、v11 包只在本地、参赛目录里被忽略的 EXE 要靠哪个包恢复。
  3. `LLM-tmp/启动客户端.md` 指向新包名，不再只指 v10。
  4. `README.md` 的「当前状态」段新增一条 2026-09-28 的发行记录并指向发行记录文档；该文件其余内容一律不动。
  5. 这四份文件里出现的包名、字节数、SHA256 与 T-02 的真实产物**逐字一致**（用命令比对，不凭记忆抄）。

---

## Corrections（更正的记录，按时间排列）

更正不是变更：它不改范围、不加工作，也不动里程碑。每一次都保留原句，旁边写更正后的说法和日期，并指向对应的 CRD。

### 2026-09-28 · T-01 的 DoD 第 1 条（更正，见 CRD 0001）

**原句（保留，未改）**：

> 两个脚本不再写死 `v10`、`20260914`、`檐下千秋-v10-Windows-x64-20260914`。版本名和日期由命令行参数给出；**缺省值仍指向现有的 v10 包，保证旧用法不变**。

**更正**：`dist/` 里并没有 `檐下千秋-v10-Windows-x64-20260914` 这个包；现在只有 `檐下千秋-v10-可玩性修复版-20260915`。所以「缺省值仍指向**现有的** v10 包」和「保证**旧用法不变**」互不相容。执行时按**「缺省目标路径与改动前逐字相同」**实现，即缺省仍为 `dist/檐下千秋-v10-Windows-x64-20260914`；同时给脚本加 `--force` 保护，避免缺省运行时覆盖 `dist/` 里已有的旧包。T-01 的 DoD 第 4 条不受影响，仍然要求 `--dry-run` 打印出的缺省目标路径是 v10 那一个。

### 2026-09-28 · T-02 的 DoD 第 7 条（更正，见 CRD 0002）

**原句（保留，未改）**：

> ZIP 小于 100 MiB（GitHub 单文件上限）；确认后**留在本地 `dist/`，不 `git add`**。

**更正**：这一条不可能通过。实测发行目录 227.7 MiB，逐文件 deflate 估算出的 ZIP 约 **153.6 MiB**（`檐下千秋.exe` 单项 231,567,256 字节 → 约 158,050,097 字节）。原因是新版素材本身已压缩过，deflate 压不动；v10 的 EXE 是 150.9 MB，这一版是 231.6 MB。执行时改为**记录真实体积，不再要求小于 100 MiB**：用户在 `pm-write-guard` 生效前已经决定这个 ZIP 不进 Git，GitHub 的单文件上限对它没有约束力；而且 153.6 MiB 本来也推不上去。T-02 的其余六条不变。实测最终 ZIP 为 **161,102,730 字节（153.6 MiB）**。

### 2026-09-28 · T-02 的 DoD 第 5 条（更正，见 CRD 0003）

**原句（保留，未改）**：

> - 日志里有 `PASS EXPORTED`，且不含 `ERROR:`；

**更正**：「不含 `ERROR:`」在本机不可能通过。真实 EXE 的日志里有且只有一行 `ERROR: Failed to read the root certificate store.`（`get_system_ca_certificates`），是本机已知的环境问题，`LLM-tmp/2026-09-28-横屏与入口更新.md` 第 21 行已记录，与本次改动无关，客户端也修不了。同一次运行里该条其余每一小段都通过：解压、逐行核对 `SHA256.txt`、目录体检干净、客户端自拉配套服务、`/healthz` 报 `content_version == 10`、退出码 `0`、8090 端口随之释放、日志里有 `PASS EXPORTED`。执行时把这半句**收窄为「除本机已知的环境提示外不含任何 `ERROR:`」**，已知提示写成显式常量，其余任何 `ERROR:` 仍判失败，判定逻辑由单元测试覆盖。
