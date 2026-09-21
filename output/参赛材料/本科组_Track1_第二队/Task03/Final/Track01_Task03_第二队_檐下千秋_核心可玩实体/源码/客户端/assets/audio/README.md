# 开发版音频素材

2026-09-14 新增。以下 WAV 由 [generate_audio.py](../../../联调脚本/generate_audio.py) 使用数学波形和固定随机种子合成，无外部采样、录音或在线运行依赖。用于当前开发版本的基础反馈，不标作真人演奏或专业配乐。

| 文件 | 用途 |
|---|---|
| ui.wav | 按钮操作 |
| ink.wav | 挥墨与技能 |
| repair.wav | 修复反馈 |
| hit.wav | 受击反馈 |
| win.wav | 任务结算 |
| ambience.wav | 环境底音循环 |
| battle.wav | 16 秒守护配乐循环 |

格式为 22050 Hz、单声道、16 位 PCM。运行 `python LLM-tmp/联调脚本/generate_audio.py` 可从仓库根目录重新生成同名资源。客户端 `soundscape.gd` 管理循环与音效池，主音量和静音设置统一生效；墨灵中文回声沿用已有实现。这批音频尚未完成真实音频设备听感验收。
