# 任务表

一个仓库一张表。每个任务行的 **Verdicts** 行由 PM 写，其余由本作业的 PM 写（本次为小作业，没有架构师）。

---

## 里程碑 M1：清理仓库冗余，保留 AI 留痕与可开发环境

**里程碑 DoD**（用户能读、能自己判断，不含任何命令）

1. 打开 `dist/` 只剩占位文件；`LLM-tmp/交付/` 不存在——旧发行包全部清掉。
2. `AI配音台词/生成音频/`、`Art_Material/Generation/生成音频/`、`LLM-tmp/客户端/assets/voice/` 三处配音都还在；`Task01/Original/AI协作记录/`、`LLM-tmp/03-AI协作留痕/`、`LLM-tmp/验证记录/`、`LLM-tmp/2026-09-14-*.md` 全部还在——AI 交互历史与迭代留痕一件没丢。
3. `.tools/` 里 `go/`、`python/`、`godot/` 与三个工具链压缩包还在；仓库里不再有旧构建产物、下载缓存或代理脚本。
4. 服务端测试仍然全绿；README 与索引文档里不再出现指向已删除文件的路径。

---

### T-01 删除旧发行包、缓存与代理脚本，并修正受影响的引用

- **里程碑**：M1
- **Shape**：solo
- **拥有文件**：见下方「删除清单」与「引用修正清单」；除此之外不改动任何文件
- **测试文件**：无。理由：本任务只做删除与文字引用修正，不产生可被单元测试覆盖的行为。按 CRD 0001，本次作业不留任何核对脚本；十四条 DoD 由 PM 直接执行命令核对，原始结果写进提交信息。
- **Verdicts**：code: not run — 本会话没有 `crew_*` 角色工具（不是 crew 预设），没有独立代码评审角色，本次为纯删除与文档引用修正，由 PM 自查，见 CRD 0002；security: skipped — 本次不触及网络、登录、权限、密钥、用户输入或新依赖，只做本地文件删除与文档改写；qa: not run — 同上，没有独立 QA 角色，十四条 DoD 由 PM 直接执行命令核对，原始结果写在提交信息里，见 CRD 0001；doc: not run — 没有独立文档评审角色

#### 删除清单

**A. 发行包整包（用户已确认全部删除）**

```text
dist/檐下千秋-Windows-x64-20260911/
dist/檐下千秋-Windows-x64-20260911.zip
dist/檐下千秋-Windows-x64-20260912/
dist/檐下千秋-Windows-x64-20260912.zip
dist/檐下千秋-v9-Windows-x64-20260914/
dist/檐下千秋-v9-Windows-x64-20260914.zip
dist/檐下千秋-v9-Windows-x64-20260914.zip.sha256
dist/檐下千秋-v10-Windows-x64-20260914/
dist/檐下千秋-v10-Windows-x64-20260914.zip
dist/檐下千秋-v10-Windows-x64-20260914.zip.sha256
LLM-tmp/交付/            （整目录，含 5 个交付包与 1 个空目录）
```

**B. 下载缓存与可重建缓存**

```text
.tools/templates-official.zip                       （1.29 GB，内容已解压到 .tools/godot/templates/）
LLM-tmp/.review/                                    （191 MB，Godot 运行期数据、日志、着色器缓存）
LLM-tmp/客户端/.godot/                              （53 MB，Godot 导入缓存，可重建）
LLM-tmp/04-工具/pylibs/                             （下载的临时 Python 依赖）
```

**C. 代理脚本、残留空目录与本机存档**

```text
.tools/ 根目录下的 63 个松散文件：除 go.zip、godot-official.zip、python-embed.zip 外全部
    （各 *_server.exe、*.py、*.ps1、*.gd、*.log、*.json、*.txt、*.go）
.tools/docx-review/  .tools/docx-v9/  .tools/docx-v9-final/
.tools/docx-v9-plan-clean/  .tools/docx-v9-plan-final/
.tools/gameover-before/  .tools/story-qa/  .tools/v10-qa/
LLM-tmp/服务端/LLM-tmp/                             （空的嵌套残留目录）
LLM-tmp/服务端/data/save.json                       （本机开发存档）
output/imagegen/model-tests/                        （空目录）
```

**D. 仓库跟踪文件里的重复项**

```text
docs/策划案要素填报表-RedHF.md                        （与 Task01/Original/策划过程/2026-08-28-策划案要素填报表-RedHF(1).md 字节完全相同）
LLM-tmp/《檐下千秋》AI产出汇总-2026-08-28.docx          （与 Task01/Original/AI协作记录/04-产出与修订/2026-08-28-《檐下千秋》AI产出汇总.docx 字节完全相同）
```

> **更正（2026-09-15）**：本组原先还列了 `output/imagegen/generate-rubbings.ps1`、`generate-dashscope-rubbings.ps1`、`generate-rubbings-fallback.ps1` 三个脚本，说它们是「代理脚本，非交付物」。删掉之后发现这个判断是错的：它们是项目自己的生图工具，`LLM-tmp/剧情版运行说明.md` 第 25/28/31 行和 `output/imagegen/生成记录.md` 第 11/40/44/55/58 行都在引用它们。三个脚本已恢复到仓库，删除清单里只剩上面这两个字节相同的文件。见 CRD 0003。

#### 必须保留（删除后仍需存在）

```text
.tools/go/  .tools/python/  .tools/godot/
.tools/go.zip  .tools/godot-official.zip  .tools/python-embed.zip
dist/.gitkeep
Task01/                          （整个目录，含 Original/AI协作记录 的全部留痕）
LLM-tmp/03-AI协作留痕/  LLM-tmp/验证记录/  LLM-tmp/2026-09-14-*.md
LLM-tmp/01-策划案/  LLM-tmp/02-叙事脚本/  LLM-tmp/服务端/  LLM-tmp/客户端/  LLM-tmp/联调脚本/
LLM-tmp/04-工具/                 （仅保留 pdftext.py 与 tech-full.txt）
docs/                            （除上面 D 组里那一个文件外全部保留）
LLM_Temp/                        （原始需求档案，保留）
AI配音台词/                      （整个目录，含 生成音频、切片、工具、台词清单）
Art_Material/                    （整个目录）
output/imagegen/                 （全部保留：三个生图 .ps1、生成记录、提示词与全部 PNG）
Official_Document/  Task02/  Task03/  SourceCode/  README.md
LLM-tmp/客户端/**/*.uid         （Godot 脚本与场景的绑定，删了会打断引用）
```

#### 引用修正清单（删完后必须同步改正）

```text
README.md                                    第 11 行指向已删除的 v10 zip；同段「正式提交目录和旧发布包保留原版本」
LLM-tmp/README.md                            第 16 行指向已删除的 v10 zip；同段「Task01/02/03、正式成果及旧发布包…」
LLM-tmp/2026-09-14-v9发行记录.md               第 3 行指向已删除的 v9 zip
LLM-tmp/启动客户端.md                          第 3 行「发行包为仓库 dist/檐下千秋-v10-…」
LLM-tmp/剧情版运行说明.md                       第 21 行「当前 Windows x64 发行包为 …」
LLM-tmp/文档版本索引.md                         第 7 行「最新素材、配音、首领与发行包」
LLM-tmp/2026-09-14-素材配音与首领更新.md         第 3 行加一句带日期的说明，原文保留（历史记录）
.gitignore                                   第 1 行 .tools/pdftext.py 已不存在且被第 2 行 /.tools 覆盖
```

#### DoD

每条都能由没写这份代码的人独立执行并得到「是 / 否」。

1. `dist/` 下除 `.gitkeep` 外没有任何文件或子目录。核对：`Get-ChildItem dist -Force` 只列出 `.gitkeep`。
2. `LLM-tmp/交付/` 不存在。核对：`Test-Path 'LLM-tmp/交付'` 为 `False`。
3. `.tools/templates-official.zip` 不存在。核对：`Test-Path '.tools/templates-official.zip'` 为 `False`。
4. `.tools/` 根目录只剩 3 个文件（`go.zip`、`godot-official.zip`、`python-embed.zip`）和 3 个目录（`go`、`python`、`godot`）。核对：`Get-ChildItem .tools -Force`。
5. `.tools/` 下 8 个临时目录全部不存在。核对：`docx-review`、`docx-v9`、`docx-v9-final`、`docx-v9-plan-clean`、`docx-v9-plan-final`、`gameover-before`、`story-qa`、`v10-qa` 逐个 `Test-Path` 为 `False`。
6. `LLM-tmp/.review/`、`LLM-tmp/客户端/.godot/`、`LLM-tmp/04-工具/pylibs/`、`LLM-tmp/服务端/LLM-tmp/`、`output/imagegen/model-tests/` 全部不存在。
7. `LLM-tmp/服务端/data/save.json` 不存在。
8. D 组 2 个跟踪文件全部不存在；`output/imagegen/` 下三个 `*.ps1` 生图工具仍然存在。核对：对 D 组两个路径与三个脚本路径各执行 `Test-Path`。**更正 2（2026-09-15）**：本条原写「D 组 5 个跟踪文件」，随 D 组更正为 2 个；理由见 `## 更正`。
9. 保留清单里每一项都存在。核对：对清单里每个路径执行 `Test-Path` 为 `True`；`dist/.gitkeep` 为 `True`。
10. 服务端测试全部通过。核对：`go -C LLM-tmp/服务端 test ./...` 输出无 `FAIL`。（2026-09-15 清理前基线：`internal/content`、`internal/httpapi`、`internal/rules`、`internal/store` 四个包全部 `ok`。）
11. 服务端静态检查无输出。核对：`go -C LLM-tmp/服务端 vet ./...` 输出为空。
12. 全仓库不再有指向已删除发行包的引用。核对：`grep -rn "dist/檐下千秋" --include=*.md .` 的结果里不含被删的四个包名。**更正 1（2026-09-15）**：本条范围收窄为「面向当前状态的文档」，带日期的历史记录保留原文字；理由见 `## 更正`。收窄后的核对方式见该节。
13. `.gitignore` 不再包含 `.tools/pdftext.py` 这一行。
14. 删除未波及跟踪文件的意外变更。核对：`git status --short` 只列出 D 组的 2 个删除、上列 7 个文档的修改（`.gitignore` 计入）、`docs/` 下本次新增的文档，以及 `output/imagegen/` 三个生图脚本的恢复；没有其它文件被改动。**更正 2（2026-09-15）**：本条原写「D 组 5 个删除」，随 D 组更正为 2 个。

---

## 更正

本表确认后出现的更正，日期均为 2026-09-15。上面确认时的原文保留不动，这一节是与它并排的说明。

### 更正 1 — DoD 第 12 条范围过宽

- **原文**：「全仓库不再有指向已删除发行包的引用。」
- **为什么不能照字面执行**：`LLM-tmp/验证记录/2026-09-14-v10/release.log`、`release-verification.json`、`README.md` 是当天的发行验证证据，里面写着发行包的完整路径；`LLM-tmp/2026-09-14-素材配音与首领更新.md` 是当天带日期的更新记录。PRD 第 2 节要求「必须保留 AI 交互历史与 AI 迭代留痕」，改写这些证据与那条要求直接冲突。
- **更正后的口径**：只要求**面向当前状态的文档**不再把已删除的发行包当作现存文件。核对范围：`README.md`、`LLM-tmp/README.md`、`LLM-tmp/启动客户端.md`、`LLM-tmp/剧情版运行说明.md`、`LLM-tmp/文档版本索引.md`、`LLM-tmp/2026-09-14-v9发行记录.md`。带日期的历史记录（`LLM-tmp/验证记录/**`、`LLM-tmp/2026-09-14-*.md`）保留原文字。
- **性质**：更正，不是变更——确认过的措辞照字面执行会与另一条确认过的要求互相矛盾。

### 更正 2 — 删除清单 D 组的三个生图脚本

- **原文**：D 组含 `output/imagegen/generate-rubbings.ps1`、`generate-dashscope-rubbings.ps1`、`generate-rubbings-fallback.ps1`，理由写的是「代理脚本，非交付物」。
- **为什么是错的**：这三个脚本被 `LLM-tmp/剧情版运行说明.md`（第 25、28、31 行）与 `output/imagegen/生成记录.md`（第 11、40、44、55、58 行）引用，是项目自己的拓印图生成工具，属于作品工具链，不符合 PRD 中「不属于作品交付物的脚本」这一条。
- **更正后的口径**：三个脚本保留在仓库；D 组只剩两个字节完全相同的文件。DoD 第 8 条从 5 个改为 2 个。
- **性质**：更正，不是变更——不是用户新要的东西，是把一个判断错误改回来。
- **相关记录**：CRD 0003。

### 已解决项 — `dist/檐下千秋-v10-Windows-x64-20260914.zip`

- 2026-09-15 首次执行时，该文件被其它进程独占（Windows 共享冲突），删不掉；当时 DoD 第 1 条没有完全满足，已如实记录。
- 用户关闭占用它的程序后立刻重试，**第一次尝试即删除成功**。
- 现在 `dist/` 中只剩 `.gitkeep`，**DoD 第 1 条已满足**，32 项删除目标全部清空。
