# macvlan-manager

CentOS 7 下的交互式 Macvlan 网络管理脚本。

## 功能

- 自动检查并加载 macvlan 内核模块
- 自动检测可用物理网卡，交互式选择
- 支持两种创建方式：
  - `ip` 命令方式（iproute2，即时生效不持久化）
  - `nmcli` 方式（NetworkManager，配置持久化）
- 支持 4 种 macvlan 模式：bridge（默认）/ private / vepa / passthru
- 一键删除所有 macvlan 接口
- 配置完成后打印完整配置总结

## 用法

```bash
sudo bash macvlan-manager.sh
```

按菜单选择操作：

```
1) 使用 ip 创建 macvlan
2) 使用 nmcli 创建 macvlan
3) 删除所有 macvlan 接口
4) 退出
```

## 交互参数

| 参数 | 说明 |
|------|------|
| 物理网卡 | 从检测到的网卡列表中选择 |
| 接口名称 | 例如 `macvlan0` |
| 模式 | bridge / private / vepa / passthru |
| IP 地址 | 例如 `192.168.1.100` |
| 子网掩码 | 默认 `255.255.255.0` |
| 网关 | 可留空 |
| DNS | 默认 `223.5.5.5` |

## 注意事项

- Macvlan 接口与宿主机**默认不能互通**，如需互通需额外配置
- 请确保目标物理网卡已连接网络
- `ip` 方式会直接改写 `/etc/resolv.conf` 为所选 DNS
- 需要 root 权限；`nmcli` 方式需要已安装 NetworkManager
