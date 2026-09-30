# v17 中文字体版

从本机已安装的中文字体中选用 Noto Serif SC 作为统一字形。Godot 的 `SystemFont` 配置保存在 `LLM-tmp/客户端/assets/fonts/chinese_system_font.tres`，并列出楷体、宋体和微软雅黑作为系统回退字体，不依赖 Godot 通用字体。`project.godot` 的自定义字体用于按钮、地图、对话和各类常规控件；战斗、探索、拓印、榫卯、技艺和图式的画布文字也改用同一字体资源。

运行截图：`font-map.png`、`trace-prologue_bridge.png`、`join-archway_form-1.png` 等。客户端专项 39 项通过；全流程可玩性回归 278 项通过，其中 761 个独特字符没有缺字，未发现水平溢出。v16 的音效、描字配乐与过渡动效保留。

正式 Windows EXE 验证通过：运行时使用中文系统字体，退出码 0，服务自动启停，发行审计无缺失或额外文件，7 项清单哈希一致。详见 `release-verification.json` 与 `console.log`。

发行包：`dist/檐下千秋-v17-中文字体版-20260929.zip`（171,166,854 字节），SHA256 `29ec6f3a0a4aa6fa6af109ad4ce4261b5420049446723979cbdf315d86f907c3`。完整解压后运行 `檐下千秋.exe`。
