# jdk1.8

CentOS 7 一键安装 JDK 1.8（OpenJDK）并配置环境变量的脚本。

## 功能

- 清理并重建 yum 软件源缓存
- 安装 `java-1.8.0-openjdk` 与 `java-1.8.0-openjdk-devel`
- 写入 `/etc/profile.d/java.sh` 配置 `JAVA_HOME` 与 `PATH`
- 验证 `java -version` 与 `javac -version`

## 用法

```bash
sudo bash jdk1.8.sh
```

## 注意事项

- 仅适用于 yum 系发行版（CentOS 7 / RHEL 7 等）
- 环境变量写入 `/etc/profile.d/java.sh`，对**新登录的会话**生效；当前会话脚本已 source 一次，可直接验证
- 安装的是 OpenJDK（开源版），不是 Oracle JDK
