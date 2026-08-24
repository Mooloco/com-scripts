# install-docker-compose

一键安装 Docker 与 Docker Compose 的脚本。

## 功能

- 使用 Docker 官方脚本（get.docker.com）安装最新 Docker
- 从 GitHub Releases 下载最新版 Docker Compose 二进制并安装到 `/usr/local/bin/docker-compose`
- 建立 `/usr/bin/docker-compose` 软链接（兼容 PATH 不含 /usr/local/bin 的环境）
- 启动并设置 docker 服务开机自启
- 自动验证 docker 与 docker-compose 版本

## 用法

```bash
sudo bash install-docker+compose.sh
```

## 注意事项

- **需要外网环境**（依赖 get.docker.com 与 GitHub Releases）
- 需要 root 权限
- 安装的是 Docker Compose **v2 二进制**（命令为 `docker-compose`），不是 apt/yum 源里的旧版
- 安装完成后建议重新登录 shell，确保 docker 命令可用
