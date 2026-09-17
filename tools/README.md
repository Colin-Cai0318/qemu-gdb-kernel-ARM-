# 本地工具目录

`./setup.sh` 在 Apple Silicon macOS 上把所有持久化依赖放在这里：

- `cache/`：Lima 下载缓存；
- `lima-<version>/`：项目私有的 Lima 二进制；
- `lima-home/`：Linux VM 配置、密钥和虚拟磁盘；
- `host-home/`：隔离后的 macOS 工具 HOME 与镜像缓存；
- `tmp/`：项目私有临时目录。

除本说明外，目录内容均被 Git 忽略。不要提交 VM 磁盘、下载包、内核源码或构建产物。
