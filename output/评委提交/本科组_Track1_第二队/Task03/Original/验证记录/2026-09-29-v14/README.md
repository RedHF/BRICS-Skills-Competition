# v14 生图水墨特效版

依据封面的黑白水墨风格，使用用户指定的 Qwen Image 3.0 兼容 API 生成 3×2 图集，提示词与原始图分别保存在 `output/imagegen/vfx/prompt.txt` 和 `output/imagegen/vfx/ink-effects-atlas.png`。本轮没有使用 Codex 内置生图。一次性密钥只进入调用进程环境，未写入素材或仓库文件。

`tools/process_vfx_atlas.py` 将六格裁成挥墨笔锋、斗拱护阵、藻井净化纹、飞檐墨刃、闪身烟迹、白蚀爆墨六张透明 PNG，运行素材保存在 `LLM-tmp/客户端/assets/vfx/`。黑底按亮度生成 alpha，保留半透明笔触；贴图原始内容由 Qwen 生成，透明化和裁切用于 Godot 播放。

客户端以贴图缩放、位移、旋转和淡出形成短动画；原先代码绘制的技能弧线、护盾圆环、净化花瓣、飞刃线条、蓄力与受击几何图形已换为这些贴图。角色、怪物、血条、方向摇杆及文字仍按各自现有方式显示。技能伤害、冷却和服务器结算规则未改。

`tests/vfx_review.gd` 在真实战斗界面验证六张透明贴图、五个技能的调用与伤害、格挡、受击和消散；22 项检查通过。截图为 `skill-0.png` 至 `skill-4.png`、`block.png`、`hit.png`、`disperse.png`。v13 的故事与可玩性回归结果继续适用。

真实导出 EXE 验证通过：六张透明特效素材全部加载，退出码 0，服务自动启停，发行包 7 项文件哈希一致，未发现缺失或多余内容；见 `release-verification.json` 与 `console.log`。

发行包：`dist/檐下千秋-v14-生图水墨特效版-20260929.zip`（165,261,971 字节），SHA256 `6c900c69b2b7359980cb77afae850c329fe165f714d4acd189603ff03d951d46`。完整解压后运行目录内的 `檐下千秋.exe`。
