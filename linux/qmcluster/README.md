# qmcluster

Proxmox VE 集群环境下的统一 VM 管理工具 —— 自动定位 VM 所在节点，跨节点执行操作。

## 为什么需要它

在 PVE 集群中，虚拟机可以在节点之间在线迁移（Live Migration），VM 所在的节点是**动态变化**的。手动管理时需要先确认 VM 在哪台节点，再登录对应节点执行 `qm` 命令，非常繁琐。

qmcluster 通过读取集群共享配置（`/etc/pve`，PMX 集群文件系统）**实时定位 VM 当前所在的节点**，然后通过 `pvesh` API 向目标节点发送操作请求。你可以在集群中的**任意节点**上，用统一的命令管理整个集群的虚拟机。

## 功能特性

- ✅ 自动定位 VM 节点，无需手动确认
- ✅ 支持 9 种常用操作：启动 / 强制停止 / 正常关机 / 重启 / 强制重置 / 挂起 / 恢复 / 状态查询 / 配置查看
- ✅ VM 迁移后自动适配，无需修改任何配置
- ✅ 基于 `pvesh` API，无需配置 SSH 免密
- ✅ 纯 Bash 实现，零依赖（仅需 PVE 自带环境）

## 安装

将脚本部署到集群中任意 PVE 节点（推荐所有节点都放一份，任意节点可管理）：

```bash
# 复制脚本到节点
scp qmcluster root@<pve-node>:/usr/local/bin/

# 赋予执行权限
ssh root@<pve-node> 'chmod +x /usr/local/bin/qmcluster'

# 验证
qmcluster status 100
```

## 使用方式

```
qmcluster <命令> <VMID>
```

### 命令列表

| 命令 | 说明 | 底层操作 |
|------|------|---------|
| `start` | 启动虚拟机 | pvesh create .../status/start |
| `stop` | 强制停止虚拟机（相当于拔电源） | pvesh create .../status/stop |
| `shutdown` | 正常关机（需安装 QEMU Guest Agent） | pvesh create .../status/shutdown |
| `reboot` | 重启虚拟机 | pvesh create .../status/reboot |
| `reset` | 强制重置虚拟机 | pvesh create .../status/reset |
| `suspend` | 挂起虚拟机 | pvesh create .../status/suspend |
| `resume` | 恢复挂起的虚拟机 | pvesh create .../status/resume |
| `status` | 查看虚拟机运行状态 | pvesh get .../status/current |
| `config` | 查看虚拟机配置 | pvesh get .../config |

### 示例

```bash
# 启动 VM 109（自动定位节点）
qmcluster start 109

# 正常关机 VM 109
qmcluster shutdown 109

# 查看 VM 109 状态
qmcluster status 109

# 查看 VM 109 完整配置
qmcluster config 109
```

执行效果：

```text
$ qmcluster start 109
[INFO] VM 109 is on node: pve-b
UPID:pve-b:0006CCEE:10A370A5:6A8C9110:qmstart:109:root@pam:
[OK] Command 'start' executed successfully on node 'pve-b'.

$ qmcluster status 109
[INFO] VM 109 is on node: pve-b
┌──────────┬───────────┐
│ key      │ value     │
╞══════════╪═══════════╡
│ status   │ running   │
└──────────┴───────────┘
[OK] Command 'status' executed successfully on node 'pve-b'.
```

## 工作原理

```
用户输入 qmcluster <命令> <VMID>
        │
        ▼
┌─────────────────────────────────────┐
│ 遍历 /etc/pve/nodes/*/qemu-server/  │
│       <VMID>.conf 查找 VM 所在节点   │
└─────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────┐
│ pvesh create/get                    │
│ /nodes/<节点>/qemu/<VMID>/status/…  │
│ （本地节点向目标节点发 API 请求）     │
└─────────────────────────────────────┘
```

- `/etc/pve` 是 PVE 集群的共享文件系统（pmxcfs），每个节点的配置对所有节点可见，因此任意节点都能定位到全集群的 VM
- `pvesh` 是 PVE 内置的 API 命令行工具，通过 Unix socket 调用本地 API 守护进程，请求会自动转发到目标节点执行

## 依赖

- Proxmox VE 集群环境（`/etc/pve` 共享配置 + `pvesh`）
- Bash 4+

## 注意事项

- `shutdown`（正常关机）需要虚拟机内安装并启用 **QEMU Guest Agent**，否则请使用 `stop` 强制停止
- 如果 VMID 不存在，脚本会报 `[ERROR] VM <VMID> not found in cluster.` 并退出
- 脚本使用 `set -u` 严格模式，参数缺失或 VMID 非数字会给出明确错误提示

## License

N/A
