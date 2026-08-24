#!/bin/bash

# 安装docker
curl -fsSL https://get.docker.com | bash -s docker
sleep 3s

# 下载dockercompose二进制文件
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

# 赋予执行权限
sudo chmod +x /usr/local/bin/docker-compose

# 建立软链接（有些环境 PATH 不包含 /usr/local/bin）
sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose

# 验证
echo ============================
echo "验证docker版本"
docker --version
echo ============================
echo "验证docker compose版本"
docker-compose version
echo ++++++++++++++++++++++++++++
systemctl  start docker
systemctl  enable docker
echo ++++++++++++++++++++++++++++
echo "完成"


