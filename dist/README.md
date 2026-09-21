# 可玩发行包

当前保留 `檐下千秋-v10-可玩性修复版-20260915.zip`，大小 92,903,008 字节（88.60 MiB），低于 GitHub 普通 Git 的单文件 100 MiB 限制。ZIP 包含客户端、服务端、内容和许可证，完整解压后运行 `檐下千秋.exe`。SHA256 见同名 `.sha256` 文件。

该版本对应参赛目录 `output/参赛材料/本科组_Track1_第二队/Task03/Final/Track01_Task03_第二队_檐下千秋_核心可玩实体/Windows-x64`。展开的客户端 EXE 约 144 MiB，不能直接入 Git；克隆后可将发行 ZIP 内游戏文件夹的全部内容复制到上述 `Windows-x64` 目录，恢复完整提交目录。源代码、文档、素材、AI 交流记录保留在仓库中。

约 674 MiB 的总参赛 ZIP 在本地保留并由 `.gitignore` 排除。它与当前游戏发行 ZIP 用途不同，不应通过 `git add -f` 强行加入。无需 Git LFS 即可获取当前全部可玩内容；未来版本应重新检查包体大小。

提交前在仓库根目录运行 `python tools/check_git_size.py --history`。超过 50 MiB 仅提示警告，达到 100 MiB 时检查失败。脚本同时检查暂存内容与未忽略的工作区文件；`--history` 检查本机全部可达历史，不读取远端未获取的提交。

参考：[GitHub 文件大小限制](https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-large-files-on-github)。
