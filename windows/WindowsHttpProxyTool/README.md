# Windows HTTP 代理工具

一个轻量级的 Windows 本地 HTTP 代理工具，使用 PowerShell 7 脚本内嵌 C# 实现。

**如需使用旧版本Powershell（Windows默认）运行，请将脚本使用utf8bom编码保存再运行！**

## 功能

- 可自定义本地端口。
- 默认监听 `127.0.0.1`，也可以监听 `0.0.0.0` 供局域网设备访问。
- 支持普通 HTTP 代理请求。
- 支持通过 `CONNECT` 建立 HTTPS 隧道。
- 无需安装额外依赖。

## 交互式运行

```powershell
powershell -ExecutionPolicy Bypass -File .\Start-HttpProxy.ps1
```

然后根据提示输入端口。

## 使用参数运行

```powershell
powershell -ExecutionPolicy Bypass -File .\Start-HttpProxy.ps1 -Port 8080
```

默认隐藏连接日志。如需显示请求和连接日志：

```powershell
powershell -ExecutionPolicy Bypass -File .\Start-HttpProxy.ps1 -Port 8080 -ShowLog
```

允许局域网访问：

```powershell
powershell -ExecutionPolicy Bypass -File .\Start-HttpProxy.ps1 -Port 8080 -ListenAddress 0.0.0.0
```

## 配置客户端

将 HTTP 代理设置为：

```text
127.0.0.1:8080
```

如果局域网中的其他设备需要使用这个代理，请使用 `0.0.0.0` 启动监听，并在其他设备上填写本机的局域网 IP 和所选端口。

## 停止

在 PowerShell 窗口中按 `Ctrl+C`。

## 说明

这是一个简单的转发代理。它不会解密 HTTPS 流量，不提供登录认证，不过滤网站，也不缓存内容。

