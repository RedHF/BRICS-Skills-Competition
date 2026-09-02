# 《檐下千秋》Godot 4 客户端

本目录是可独立运行的 Godot 4 客户端演示。当前内容覆盖序章「风雨廊桥」和第一章「社庙」的三个事件，包含调查叙事、数据驱动谜题、轻战斗、心舍记忆抉择和章节结算，完整流程可连续体验约 3 分钟以上。

## 运行

1. 安装 Godot 4.2 或更新版本。
2. 在 Godot Project Manager 中导入本目录，打开 `project.godot`。
3. 点击 Run Project（或命令行执行 `godot --editor --path .`）。
4. 服务端默认地址为 `http://127.0.0.1:8090`，可在项目设置中修改 `yanxia/server_url`。启动时客户端会用 `user://yanxia_identity.cfg` 中的玩家 ID 创建/读取同一份服务器存档（该文件只保存身份指针，不保存进度）；服务端不可用时自动切换为「本地演示模式」，本地进度只存在内存中，不会伪装成服务器存档。

## 目录约定

- `content/chapters.json`：版本化章节、事件、谜题步骤、战斗参数和奖励目录。新增章节通常只需增加 JSON 节点。
- `content/chapters.json` 顶层 `art`：按事件 ID 配置 `backdrop_color` 和可选 `background` 资源路径；缺少素材时自动回退占位色块。
- `content/story_text.json`：演出文本与章节收束文本，与事件 ID 关联，便于编剧独立扩写。
- `scripts/data_repository.gd`：内容加载与章节/事件查询。
- `scripts/main.gd`：UI 状态机和演出流程；谜题、战斗、抉择均通过数据生成控件。
- `scripts/network_client.gd`：HTTP API 适配层。客户端提交的是步骤、操作记录和战斗遥测，分数与结算以服务端响应为准。
- `scripts/game_state.gd`：当前会话快照、记忆账册和离线演示状态。正式存档应由服务端持久化。

## 联网协议钩子

客户端使用以下 REST 路径（服务端可在不改客户端 UI 的情况下扩展响应字段）：

- `POST /api/v1/players`
- `GET /api/v1/players/{player_id}`
- `POST /api/v1/events/{chapter_id}/{event_id}/start`
- `POST /api/v1/sessions/{session_id}/puzzle`
- `POST /api/v1/sessions/{session_id}/battle`
- `POST /api/v1/sessions/{session_id}/choice`
- `POST /api/v1/sessions/{session_id}/finish`（服务端同时保留 `/submit` 兼容路径）

每次联网操作均带 `session_id`；客户端不会用本地计算结果覆盖在线快照。网络超时后才会显式转入本地演示模式，便于比赛现场无服务端时展示玩法。

服务器明确判定谜题尝试用尽、侵蚀度超限或战斗失败时，原事件会话会被冻结；客户端会清空旧 `session_id`，只有点击“重新开始事件”后才创建新的服务器会话。这样重试不会绕过服务端的次数和结算校验。
