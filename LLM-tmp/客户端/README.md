# 客户端

使用 Godot 4.5.2。发布 EXE 及完整运行方式见上级 `启动客户端.md`。

540×960 竖屏布局，固定底部导航。

`battle_arena.gd` 绘制敌人、血量、攻击预警和技能反馈。`main.gd` 负责地图、事件、心舍、战斗和账册；`trace_canvas.gd` 采集鼠标笔画并绘制同服务端规格一致的容差带；`network_client.gd` 负责 HTTP 边界错误；`data_repository.gd` 用稳定 ID 读取服务端目录。

客户端不携带谜题文字答案，也不在断网时模拟奖励。内容全部由 `/api/v1/catalog` 提供，运行状态以服务端为准。

`tests/integration.gd` 覆盖序章和完整社庙，使用实际画布输入事件并加入手部偏移，验证失败笔画标记和单笔修正、实际攻击/护盾/净化/冷却/失败、语音播放进度与暂停；战斗时钟在测试中加速。该测试脚本不导出到发布程序。

`export_presets.cfg` 配置 Windows x64 可执行文件及嵌入资源。构建机需要 Godot 4.5.2 和同版本 Windows 导出模板；用户运行发布版不需要这些工具。

开屏 Logo 源文件为 `assets/logo.svg`，`logo.png` 用于 Godot 引擎启动画面。登录令牌仅驻留 `network_client.gd` 内存，HTTP 请求携带 Authorization，401 会回到登录页。第三方平台适配器连接 `third_party_login_requested` 信号并调用 `login_external`，服务端必须验证平台凭证；发行版未注册具体平台。
