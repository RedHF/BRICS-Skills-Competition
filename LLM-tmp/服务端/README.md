# 《檐下千秋》服务端

Go 实现的轻量本地服务器，为 Godot 客户端提供剧情目录、规则校验和 JSON 存档。当前版本免登录、单机匿名游玩；不会创建账号、签发令牌或连接第三方身份服务。内容定义在 `content/chapters.json`，新增章节/事件/谜题只需添加 JSON 数据，不修改 HTTP 或规则代码。客户端默认地址为 `http://127.0.0.1:8090`。内容与墨灵的维护规则详见 `content/README.md`。

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

`data/save.json` 由服务器独占保存本地匿名玩家进度、会话、记忆账册与结算结果。写入采用临时文件替换；示例环境不依赖数据库。存档不上传云端，也不包含账号凭证。

## API

以下接口均为本地匿名会话接口，不需要 `Authorization` 请求头；`player_id` 由本地服务首次启动时生成并保存在 JSON 存档中，仅用于恢复同一设备进度。

所有请求和响应均为 JSON；请求体禁止未知字段，单个请求最大 512 KiB。答案键只存在 `content/chapters.json`，`GET /api/v1/catalog` 会隐藏答案。

| 方法 | 路由 | 用途 |
|---|---|---|
| GET | `/healthz` | 健康检查与内容版本 |
| GET | `/api/v1/catalog` | 获取章节、事件、文本、谜题提示和公开规则 |
| POST | `/api/v1/players` | 读取/更新本地匿名玩家显示名，body `{player_id?,display_name?}` |
| GET | `/api/v1/players/{id}` | 获取服务器存档 |
| GET | `/api/v1/players/{id}/ledger` | 获取记忆账册 |
| POST | `/api/v1/sessions` | 开始事件，body `{player_id,chapter_id,event_id}` |
| POST | `/api/v1/events/{chapter}/{event}/start` | 开始事件的兼容写法，body `{player_id}` |
| GET | `/api/v1/sessions/{id}` | 恢复会话 |
| POST | `/api/v1/sessions/{id}/puzzle` | 提交一个按顺序的谜题动作，普通步骤 `{step_id,answer}`；拓印 `{step_id,strokes:[[[x,y],...],...]}` |
| POST | `/api/v1/sessions/{id}/battle` | 提交战斗操作时间线，body `{player_id?,actions:[{skill,at_ms}],duration_ms,waves_cleared?,hits_taken?}` |
| POST | `/api/v1/sessions/{id}/choice` | 记忆选择，body `{player_id?,action,forget_memory_id?}` |
| POST | `/api/v1/sessions/{id}/finish`（或 `/settle`） | 服务器重算星级/墨痕并原子写入存档 |

早期客户端也可以使用 `/api/v1/runs`、`/actions`、`/memory`、`/submit` 作为对应别名。
客户端若采用 `/api/v1/events/{chapter}/{event}/start` 和 `/settle` 命名，也已提供兼容路由。

## 校验规则

内容协议为版本 7。抉择发生在战斗前，获得与遗忘立即原子写入，随后结算发奖。每星对应一点墨痕；章节按事件顺序开放。拓印展示与服务器共享 aspect_ratio 和 tolerance，支持宽容差。


- 章节必须已解锁；谜题按 JSON 定义的步骤顺序提交，答案由服务器比较，非描摹步骤错误增加 10 点侵蚀度并受最大尝试次数限制；描摹失败返回 `failed_strokes` 供单笔修正，不扣侵蚀。
- 战斗必须在规定时长内、按时间顺序提交已拥有的技能；服务器按事件 JSON 的 `required_skills` 检查已施展技能，并根据 `skills` 的伤害、冷却、护盾和净化数值以及每 3 秒一次的敌人攻击重算波数和受蚀；忽略客户端声明的波数及受击数，失败增加 15 点侵蚀度，受击每次增加 5 点。技能名称不写死在规则代码中，新增技能名称可直接扩展目录。
- 记忆选择只能使用事件提供的选项；容量不足时必须提交已有记忆 ID 进行遗忘。
- `finish` 不接受客户端分数或奖励，服务器按谜题得分、战斗结果、错误次数和侵蚀阶段重算 1–3 星、墨痕和容量扩展。重复结算返回同一结果，不会重复发奖。
- 会话与玩家更新使用同一持久化事务，避免只写入奖励而丢失事件记录。

## 检查

```powershell
go test ./...
go build ./cmd/server
```

## 回溯与继续（协议 7）

GET /api/v1/sessions 返回当前本地玩家最近未完成事件（没有则 session 为 null）。重复开始返回该事件。POST /api/v1/sessions/{id}/rewind 提交当前 retries 整数；失败事件恢复起点侵蚀与谜题并保留已获得墨灵，消耗 1 墨痕，序章在无墨痕时免费。请求重复不会重复扣费。

事件不再执行固定墙钟超时；战斗仍按配置 duration_sec 校验。记忆保留数量和白蚀清除比例额外展示，星级权重本轮不调整。

## 剧情与静态拓印资源

目录当前包含五章十任务（序章廊桥、社庙三任务、戏楼两任务、牌坊两任务、通天塔两任务），任务对话、三条调查线索、结语和终章三种等价回应均由 `chapters.json` 提供。每道拓印绑定 `客户端/assets/rubbings/` 下的一张静态 PNG；服务器只校验轨迹并返回稳定资源路径，不在运行时请求 image2.5 或生成图片。
