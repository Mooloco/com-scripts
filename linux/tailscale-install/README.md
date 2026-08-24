# tailscale-install

一键安装最新版 Tailscale（Linux）的脚本。

> 注意：本脚本是 **Tailscale 官方安装脚本**（<https://tailscale.com/install.sh>）的存档副本，版权归 Tailscale Inc & AUTHORS，BSD-3-Clause 许可。

## 功能

- 自动检测系统发行版与版本，选择对应的安装方式
- 支持 Debian/Ubuntu 系（apt）、CentOS/RHEL/Fedora 系（yum/dnf）、Arch 系（pacman）、Alpine（apk）、openSUSE（zypper）、FreeBSD（pkg）等主流发行版
- 自动校验发行版版本是否在官方支持列表内

## 用法

```bash
sudo bash tailscale-install.sh
```

## 环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `TRACK` | 安装通道：`stable` / `unstable` | `stable` |
| `TAILSCALE_VERSION` | 固定安装指定版本，例如 `1.88.4` | 最新版 |

示例：

```bash
sudo TRACK=unstable bash tailscale-install.sh
sudo TAILSCALE_VERSION=1.88.4 bash tailscale-install.sh
```

## 安装后

```bash
sudo tailscale up          # 登录并启动
tailscale status           # 查看状态
```

## 注意事项

- 需要外网环境（依赖 pkgs.tailscale.com）
- 需要 root 权限（脚本内部会尝试 sudo）
- 推荐直接从官方渠道获取最新版：`curl -fsSL https://tailscale.com/install.sh | sh`
