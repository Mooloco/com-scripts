# SSH MOTD — Windows OpenSSH 登录横幅(PowerShell 7)

Windows OpenSSH 服务器交互式登录时显示的系统信息横幅脚本(Windows Logo + 系统/域/CPU/内存/磁盘/网络信息),专为 PowerShell 7(`pwsh`)设计。

## 背景

Windows OpenSSH 将默认 shell 设为 `pwsh.exe` 后,**每次 SSH 会话(包括非交互会话)都会加载 PowerShell profile**。未加防护的 profile 会导致两个问题:

1. **SFTP / SCP 异常**:横幅输出到 stdout,污染传输协议流,客户端报 `Received message too long` 并断开;
2. **无意义的报错**:`Clear-Host` 在非交互会话的隐藏控制台上设置光标位置失败,抛出 `SetValueInvocationException: ... $RawUI.CursorPosition`。

本脚本在开头加了**交互式守卫**,非交互会话直接跳过,只对真正的交互式登录(SSH PTY / 本地控制台)显示横幅。

## 部署

1. 将 `Microsoft.PowerShell_profile.ps1` 复制到当前用户的 PowerShell 7 profile 路径:

   ```
   C:\Users\<用户名>\Documents\PowerShell\Microsoft.PowerShell_profile.ps1
   ```

   (若目录不存在则新建;该文件名不可更改,否则不会作为 profile 加载)

2. 确认 OpenSSH 默认 shell 为 PowerShell 7(注册表):

   ```
   HKLM:\SOFTWARE\OpenSSH
   DefaultShell = C:\Program Files\PowerShell\7\pwsh.exe
   ```

3. 重新建立 SSH 连接即可看到横幅;SFTP / SCP / 远程命令不受影响。

> 其他用户要看到横幅,需给其各自的 profile 路径放置一份,或放到 AllUsers 级 profile:`C:\Program Files\PowerShell\7\profile.ps1`。

## 工作原理

```powershell
# 仅交互式登录(SSH PTY 会话 / 本地控制台)时显示 MOTD。
# SFTP / SCP / rsync / git / 远程执行命令等非交互会话直接跳过,
# 避免横幅输出污染传输协议流导致 "Received message too long" 等异常。
if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) { return }
```

- 非交互会话:stdin/stdout 为管道(重定向)→ 直接跳过,无任何输出;
- 交互式 SSH 登录:服务器分配 ConPTY,stdin/stdout 为真实控制台 → 正常显示横幅。

## 实测验证

| 场景 | 结果 |
|---|---|
| `ssh host "命令"`(非交互) | 干净输出,无横幅、无报错 |
| `sftp` | 正常,协议流无污染 |
| `ssh` 交互式登录(PTY) | 横幅正常显示 |

## 显示内容

- 操作系统 / 版本 / 架构 / 主机名 / 域 / 当前用户 / PowerShell 版本
- 系统运行时间 / CPU 使用率与型号 / 内存使用
- IPv4 地址 / SSH 来源 IP / 当前时间
- 各磁盘空间占用

## 作者

Mooloco
