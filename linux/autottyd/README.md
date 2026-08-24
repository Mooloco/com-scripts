# autottyd

为 PVE 虚拟机一键启用串口控制台登录（ttyS0）的脚本。

## 功能

- 自动识别系统发行版（Ubuntu / CentOS 7 / Debian），也支持手动指定
- 自动判断启动模式（UEFI / BIOS）
- 备份 `/etc/default/grub` 后追加 `console=tty0 console=ttyS0,115200n8` 内核参数
- 按系统重新生成 grub.cfg（`update-grub` / `grub2-mkconfig`）
- 启用并启动 `serial-getty@ttyS0.service` 串口登录服务

## 前提条件

- PVE 虚拟机需要在「硬件」中添加一个**串口（Serial 0）**作为入口
- 以 root 运行（或 sudo）

## 用法

```bash
chmod +x autottyd.sh
sudo ./autottyd.sh
```

按提示选择系统（1. Ubuntu Server 25.04 / 2. CentOS 7.9 / 3. Debian 13 / 4. 使用自动识别结果），确认后自动配置。

## 支持的系统

| 系统 | 说明 |
|------|------|
| Ubuntu Server 25.04 | 修改 `GRUB_CMDLINE_LINUX_DEFAULT`，`update-grub` |
| CentOS 7.9 | 修改 `GRUB_CMDLINE_LINUX`，`grub2-mkconfig`（自动区分 UEFI/BIOS） |
| Debian 13 | 同 Ubuntu 方式 |

## 注意事项

- 脚本会备份原 grub 配置为 `/etc/default/grub.bak.<时间戳>`
- 配置完成后**需要重启系统生效**，脚本末尾会询问是否立即重启
- 重启后在 PVE 界面 **Console → Serial0** 查看串口登录效果
