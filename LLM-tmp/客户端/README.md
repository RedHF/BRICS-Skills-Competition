# 客户端

使用 Godot 4.5.2。发布 EXE 及完整运行方式见上级 `启动客户端.md`。

`main.gd` 负责地图、事件、心舍、战斗和账册；`trace_canvas.gd` 采集鼠标笔画并绘制同服务端规格一致的容差带；`network_client.gd` 负责 HTTP 边界错误；`data_repository.gd` 用稳定 ID 读取服务端目录。

客户端不携带谜题文字答案，也不在断网时模拟奖励。内容全部由 `/api/v1/catalog` 提供，运行状态以服务端为准。

`tests/integration.gd` 覆盖序章和完整社庙，使用实际画布输入事件并加入手部偏移，战斗时钟在测试中加速。该测试脚本不导出到发布程序。

`export_presets.cfg` 配置 Windows x64 可执行文件及嵌入资源。构建机需要 Godot 4.5.2 和同版本 Windows 导出模板；用户运行发布版不需要这些工具。
