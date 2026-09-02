# 《檐下千秋》服务端

标准库 Go 实现的轻量服务器，为 Godot 客户端提供联网存档与服务端结算。内容定义在 `content/chapters.json`，新增章节/事件/谜题只需添加 JSON 数据，不修改 HTTP 或规则代码。客户端项目已将默认地址配置为 `http://127.0.0.1:8090`；顶层 `art` 映射支持事件占位色和后续背景资源路径。

## 运行

需要 Go 1.22 或更高版本：

```powershell
cd LLM-tmp/服务端
go run ./cmd/server
```

也可以从仓库根目录直接运行 `go -C LLM-tmp/服务端 run ./cmd/server`；启动程序会自动定位默认内容文件。

默认监听 `http://127.0.0.1:8090`。部署时可以指定：

```powershell
go run ./cmd/server -addr :8090 -content ./content/chapters.json -data ./data/save.json
```

`data/save.json` 由服务器独占保存玩家进度、会话、记忆账册与结算结果。写入采用临时文件替换；示例环境不依赖数据库，后续可将 `internal/store` 替换为数据库实现。

## API

所有请求和响应均为 JSON；请求体禁止未知字段，单个请求最大 512 KiB。答案键只存在 `content/chapters.json`，`GET /api/v1/catalog` 会隐藏答案。

| 方法 | 路由 | 用途 |
|---|---|---|
| GET | `/healthz` | 健康检查与内容版本 |
| GET | `/api/v1/catalog` | 获取章节、事件、文本、谜题提示和公开规则 |
| POST | `/api/v1/players` | 创建/恢复玩家，body `{player_id?,display_name?}` |
| GET | `/api/v1/players/{id}` | 获取服务器存档 |
| GET | `/api/v1/players/{id}/ledger` | 获取记忆账册 |
| POST | `/api/v1/sessions` | 开始事件，body `{player_id,chapter_id,event_id}` |
| POST | `/api/v1/events/{chapter}/{event}/start` | 开始事件的兼容写法，body `{player_id}` |
| GET | `/api/v1/sessions/{id}` | 恢复会话 |
| POST | `/api/v1/sessions/{id}/puzzle` | 提交一个按顺序的谜题动作，body `{player_id?,step_id,answer,action?}` |
| POST | `/api/v1/sessions/{id}/battle` | 提交战斗遥测，body `{player_id?,actions:[{skill,at_ms}],duration_ms,waves_cleared?,hits_taken?}` |
| POST | `/api/v1/sessions/{id}/choice` | 记忆选择，body `{player_id?,action,forget_memory_id?}` |
| POST | `/api/v1/sessions/{id}/finish`（或 `/settle`） | 服务器重算星级/墨痕并原子写入存档 |

早期客户端也可以使用 `/api/v1/runs`、`/actions`、`/memory`、`/submit` 作为对应别名。
客户端若采用 `/api/v1/events/{chapter}/{event}/start` 和 `/settle` 命名，也已提供兼容路由。

## 校验规则

- 章节必须已解锁；谜题按 JSON 定义的步骤顺序提交，答案由服务器比较，错误增加 10 点侵蚀度并受最大尝试次数限制。
- 战斗必须在规定时长内、按时间顺序提交已拥有的技能；服务器按事件 JSON 的 `required_skills` 校验技能、波数、受击次数和战斗时长，失败增加 15 点侵蚀度，受击每次增加 5 点。技能名称不写死在规则代码中，新增记忆技能可直接扩展目录。
- 记忆选择只能使用事件提供的选项；容量不足时必须提交已有记忆 ID 进行遗忘。
- `finish` 不接受客户端分数或奖励，服务器按谜题得分、战斗结果、错误次数和侵蚀阶段重算 1–3 星、墨痕和容量扩展。重复结算返回同一结果，不会重复发奖。
- 会话与玩家更新使用同一持久化事务，避免只写入奖励而丢失事件记录。

## 检查

```powershell
go test ./...
go build ./cmd/server
```
