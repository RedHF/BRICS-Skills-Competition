# PRD：打包可玩发行版 v11

- 作业 slug：`release-v11`
- 版本：v1（2026-09-28）
- 语言：中文（代码、注释、提交信息、`README.md` 仍为英文；`README.md` 的例外见第 5 节）

## 1. 目标

用户原话：「打包一个发行版」

**问题。** 仓库里最新的可玩发行包是 `dist/檐下千秋-v10-可玩性修复版-20260915.zip`（88.6 MiB，构建于 2026-09-15）。它之后源码又变了三次，**全部没有进任何发行包**：

| 日期 | 改动 | 记录 |
|---|---|---|
| 2026-09-28 | 横屏与入口更新：1280×720 横屏、独立欢迎页与五章关卡选择页、新版背景与 Logo | `LLM-tmp/2026-09-28-横屏与入口更新.md` |
| 2026-09-28 | 水墨 UI 与流程简化：主页／关卡／游戏三页，纸卡与墨刷主题 | `LLM-tmp/2026-09-28-水墨UI与流程简化.md` |
| 2026-09-28 | Qwen 配音重制：184 段语音全部换成 Qwen Audio 3.1 TTS Flash | `LLM-tmp/2026-09-28-Qwen配音重制.md` |

**谁有这个问题。** 要试玩、要给评审演示、或要把作品交出去的人。他们现在只能拿到 2026-09-15 的旧包，看到的是旧界面和旧配音。

**要什么。** 从**当前源码**（工作区现状，含尚未提交的改动）重新构建一个 Windows x64 可玩发行包：完整解压后双击 `檐下千秋.exe` 就能玩，不需要安装 Godot 或 Go。

**交付物**

| # | 交付物 | 位置 |
|---|---|---|
| 1 | 发行目录：客户端 EXE、服务端 EXE、`chapters.json`、运行说明、第三方许可、逐文件 `SHA256.txt` | `dist/檐下千秋-v11-横屏水墨版-20260928/` |
| 2 | 发行 ZIP 与 ZIP 校验值 | `dist/檐下千秋-v11-横屏水墨版-20260928.zip` 与 `.zip.sha256` |
| 3 | 隔离解压 + 真机运行验证结果 | `LLM-tmp/验证记录/2026-09-28-v11/` |
| 4 | 发行记录 | `LLM-tmp/2026-09-28-v11发行记录.md` |
| 5 | 面向读者与提交者的说明更新 | `dist/README.md`、`LLM-tmp/启动客户端.md`、`README.md` |
| 6 | 可复现的打包与校验脚本 | `LLM-tmp/联调脚本/package_release.py`、`LLM-tmp/联调脚本/verify_release.py` |

**版本号。** 本包发行版本号为 **v11**；**内容协议仍是 v10**（服务端 `buildID = assets-boss-v10`，客户端会拒绝协议不匹配的服务端）。这两个号不是一回事，发行记录里分开写清楚。

## 2. 不在范围内

- **不做完整参赛提交包。** `output/参赛材料/本科组_Track1_第二队.zip`（674 MiB，2026-09-21 构建）本次不重建、不改动，`Task01/`、`Task02/`、`Task03/`、`Official_Document/` 也不动。
- **不改任何游戏源码、内容 JSON、场景与素材的内容。** 本次只构建与打包，不改行为。唯一的例外是 `LLM-tmp/联调脚本/` 下两个发行脚本，它们本来就属于构建工具。
- **不把新发行 ZIP 提交进 Git。** 它只在本地 `dist/`，已被 `/dist/*` 规则忽略。理由：`.git` 已经 1037 MiB。
- **不提交当前工作区里 2026-09-28 的源码改动**（约 397 个已跟踪文件 + 435 个未跟踪文件）。它们保持原样，属于前一轮未完成的工作。
- **不删除旧的 v10 发行 ZIP。** 它是仓库里唯一能恢复 `output/参赛材料/.../Windows-x64/` 下被忽略 EXE 的东西。
- **不推送、不打标签、不合并、不删分支。** 提交由我执行；其余每一项都要你当场单独同意。
- **不给 Word/PDF 做渲染验证。** 本机没有 LibreOffice（2026-09-28 的记录里已经确认）。

## 3. 面试已确认的事项

| # | 问题 | 结论 |
|---|---|---|
| 1 | 本会话没有 `crew_*` 角色工具，怎么办 | 由 PM 单独执行。没有独立工程师、QA 和评审角色，写和检查是同一人 |
| 2 | 文档与对话语言 | 中文（代码、注释、提交信息、`README.md` 仍为英文） |
| 3 | 打包范围 | 只打可玩发行包，不打完整参赛提交包 |
| 4 | 提交策略 | 发行 ZIP 不进 Git；本次只提交发行记录与打包脚本 |

## 4. Language and stack

本仓库已有固定技术栈，本次不重新选型，只确认。

| 项 | 内容 |
|---|---|
| 客户端语言与版本 | Godot **4.5.2**，GDScript。工程 `LLM-tmp/客户端/project.godot`（`config_version=5`） |
| 客户端导出器 | `.tools/godot/Godot_v4.5.2-stable_win64_console.exe`。本机 PATH 上没有 Godot，只能用它 |
| 导出模板 | `.tools/godot/templates/windows_release_x86_64.exe`，`version.txt` 声明 4.5.2；`export_presets.cfg` 已按相对路径引用，资源内嵌（`embed_pck=true`） |
| 服务端语言与版本 | Go，模块 `yanxia-server`，`go.mod` 声明 `go 1.22`。本机 `go1.27.1 windows/amd64` |
| 打包与校验语言 | Python 3（本机 `3.14.6`），只用标准库 |
| 包管理器 | 服务端用 Go modules；客户端和 Python 工具没有包管理器 |
| 测试框架 | 服务端：Go 原生 `testing`；客户端：手写 GDScript，位于 `LLM-tmp/客户端/tests/`；Python 工具：`unittest` |
| 确切测试命令 | 服务端 `go -C LLM-tmp/服务端 test ./...`；客户端 `& ".tools/godot/Godot_v4.5.2-stable_win64_console.exe" --headless --path "LLM-tmp/客户端" --script res://tests/<名字>.gd`；Python 工具 `python -m unittest discover -s "LLM-tmp/联调脚本" -p "test_release_tools.py" -v` |
| 手工运行 | 发行包：解压后双击 `檐下千秋.exe`。开发：先 `go -C LLM-tmp/服务端 run ./cmd/server`，再用 Godot 打开 `客户端/project.godot` |
| 未能在本机验证 | 客户端 GDScript 测试需要 Godot 先导入一次工程。本次会先导出再验证**导出后的 EXE**，所以这条不构成阻塞 |

## 5. 与 crew 模板的偏差（写在这里，确认时可以推翻）

1. **不新建 `README-zh.md`。** crew 模板要求 `README.md` 是英文、另配一份本语言版本。本仓库的 `README.md` 从第一天起就是中文，而且是赛题提交说明，改写成英文会破坏它。所以本次**保持 `README.md` 为中文**，不建重复文件。
2. **不新建 `CHANGELOG.md`。** 本仓库没有这个文件，它用 `LLM-tmp/` 下带日期的记录文档代替。本次沿用该惯例。
3. **`docs/tasks/README.md` 在 `main` 上还不存在。** 上一次 crew 作业（`repo-cleanup`）也建过它，但那个分支 `crew/repo-cleanup` 至今没有合并。本次在 `main` 的基础上新建这张表；如果以后合并那个分支，这两份需要人工合一。

## 6. 完成判据

见 `docs/tasks/README.md`。里程碑 M1 的 DoD 写明「做完是什么样」，三条任务行的 DoD 写明「谁、用什么命令核对」。
