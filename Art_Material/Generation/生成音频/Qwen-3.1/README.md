# Qwen 配音来源记录

最终184段音频仅存于 `LLM-tmp/客户端/assets/voice/`。本目录保留合并后的 `generation-report.json`，包含模型、声线、原文、请求ID和最终文件哈希。

重复WAV和逐条临时JSON已清理。生成工具改在被忽略的 `.review/qwen-tts/` 中暂存，全部成功后由 `--install` 接入游戏。记录中的 file 是生成阶段角色相对路径，最终资源以该路径的文件名定位。
