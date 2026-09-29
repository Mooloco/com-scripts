# Intel X520 SR-IOV VF 管理脚本

一个用于 Proxmox VE / Debian 系环境的 Intel X520 SR-IOV VF 管理脚本。

该脚本主要用于管理指定物理网卡（PF）的 SR-IOV VF 数量，并为每个 VF 自动分配固定 MAC 地址，同时生成 systemd 服务，在系统重启后自动恢复 VF 数量和 MAC 配置。

---

## 功能

脚本当前支持：

- 查看指定网卡当前 VF 数量
- 查看硬件支持的最大 VF 数量
- 在当前 VF 数量基础上增加 1 个 VF
- 将 VF 数量置 0
- 按预设数量重新初始化 VF
- 自动为每个 VF 分配固定 MAC 地址
- 自动开启 `spoofchk`
- 删除 VF 前检查对应 VFIO/IOMMU Group 是否正在被虚拟机进程占用
- 对已绑定 `vfio-pci`、但实际未被虚拟机使用的 VF 自动解绑
- 自动生成独立的开机初始化脚本
- 自动生成并启用 systemd 服务
- 系统重启后自动恢复 VF 数量和固定 MAC

---

## 适用环境

主要面向以下环境：

- Proxmox VE
- Debian
- 支持 SR-IOV 的 Intel X520 网卡
- Linux 内核已经启用 IOMMU / SR-IOV
- PF 网卡已经能够正常创建 VF

理论上也可以适配其他支持：

```text
/sys/class/net/<interface>/device/sriov_numvfs
```

的 SR-IOV 网卡，但本脚本主要基于 Intel X520 编写和测试。

---

## 文件说明

主脚本：

```text
x520-vf.sh
```

脚本执行后会自动生成：

```text
/usr/local/sbin/x520-sriov-nic1-init.sh
/etc/systemd/system/x520-sriov-nic1.service
```

其中：

### `/usr/local/sbin/x520-sriov-nic1-init.sh`

负责真正执行：

- 创建 VF
- 恢复 VF 数量
- 设置每个 VF 的固定 MAC
- 开启 spoof checking

### `/etc/systemd/system/x520-sriov-nic1.service`

systemd 服务本身只负责调用初始化脚本：

```ini
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/x520-sriov-nic1-init.sh
RemainAfterExit=yes
```

这种设计避免把复杂 Bash 命令直接写进 `ExecStart=`，同时避免 systemd 对 `%` 等字符进行额外解析而导致 unit 文件出现 `bad-setting`。

---

## 默认配置

脚本顶部有三个最常用的配置项：

```bash
DEFAULT_VFS=6
IFACE="nic1"
MAC_PREFIX="02:52:00:02:01"
```

### `DEFAULT_VFS`

默认初始化的 VF 数量。

例如：

```bash
DEFAULT_VFS=6
```

表示选择“按脚本设定值初始化”时，会创建 6 个 VF。

---

### `IFACE`

X520 的物理接口名称。

例如：

```bash
IFACE="nic1"
```

请根据实际系统修改。

可以通过以下命令查看接口名称：

```bash
ip link
```

或：

```bash
ls /sys/class/net/
```

---

### `MAC_PREFIX`

VF 固定 MAC 地址的前 5 个字节。

例如：

```bash
MAC_PREFIX="02:52:00:02:01"
```

脚本会自动使用 VF 编号生成最后 1 个字节：

```text
VF0 -> 02:52:00:02:01:00
VF1 -> 02:52:00:02:01:01
VF2 -> 02:52:00:02:01:02
VF3 -> 02:52:00:02:01:03
VF4 -> 02:52:00:02:01:04
VF5 -> 02:52:00:02:01:05
```

`02` 开头表示 Locally Administered Address，适合用于自定义本地 MAC。

---

## 安装

下载脚本后赋予执行权限：

```bash
chmod +x x520-vf.sh
```

然后使用 root 执行：

```bash
./x520-vf.sh
```

---

## 菜单说明

启动后会看到类似：

```text
================================================
 Intel X520 SR-IOV VF 管理工具
================================================

接口：nic1
当前 VF 数量：6
脚本默认 VF 数量：6
硬件最大 VF 数量：63
固定 MAC 前缀：02:52:00:02:01
开机初始化脚本：/usr/local/sbin/x520-sriov-nic1-init.sh
systemd 服务：x520-sriov-nic1.service

1) 保持当前数量并增加 1 个 VF
2) VF 数量置 0
3) 按脚本设定值初始化 VF
4) 退出
```

### 选项 1：增加 1 个 VF

例如当前：

```text
6 VF
```

执行后：

```text
6 -> 0 -> 7
```

脚本会重新创建 VF，并重新写入全部固定 MAC。

---

### 选项 2：VF 数量置 0

将：

```text
sriov_numvfs
```

设置为：

```text
0
```

同时更新开机配置，使重启后 VF 数量保持为 0。

---

### 选项 3：按脚本设定值初始化

例如：

```bash
DEFAULT_VFS=6
```

执行过程类似：

```text
当前 VF -> 0 -> 6
```

然后自动恢复：

```text
VF0 -> 固定 MAC
VF1 -> 固定 MAC
...
VF5 -> 固定 MAC
```

这是推荐的重新初始化方式。

---

## VF 使用状态检测

脚本在删除或重新创建 VF 前，不会简单地通过：

```text
driver = vfio-pci
```

来判断 VF 是否正在使用。

因为一个 VF 即使已经绑定：

```text
vfio-pci
```

也不代表它一定正在被虚拟机占用。

脚本会进一步获取 VF 所在的：

```text
IOMMU Group
```

然后扫描：

```text
/proc/*/fd/
```

检查是否有进程打开：

```text
/dev/vfio/<group>
```

如果发现 VF 正在被 QEMU / VM 等进程占用，会停止操作，例如：

```text
VF 0000:02:10.0 所在 IOMMU 组 15 正被进程 1234 (qemu-system-x86) 使用。
请先停止使用该 VF 的虚拟机，然后重试。
```

这样可以避免误删正在运行中的 VF。

---

## VFIO 自动解绑

如果 VF 已经绑定：

```text
vfio-pci
```

但实际上没有任何虚拟机进程正在使用它，脚本会在删除 VF 前自动执行解绑：

```bash
echo "<PCI_ADDRESS>" > /sys/bus/pci/drivers/vfio-pci/unbind
```

然后再修改：

```text
sriov_numvfs
```

这样可以避免由于空闲 VF 仍绑定在 `vfio-pci` 而导致：

```text
Device or resource busy
```

等问题。

---

## 固定 MAC

VF 创建完成后，脚本通过 PF 设置 VF MAC：

```bash
ip link set dev nic1 vf 0 mac 02:52:00:02:01:00 spoofchk on
```

因此虚拟机内部通常不需要再手动修改 MAC。

同时启用：

```text
spoofchk on
```

可以阻止虚拟机随意伪造其他源 MAC。

查看当前 VF 配置：

```bash
ip link show nic1
```

可以看到类似：

```text
vf 0 MAC 02:52:00:02:01:00, spoof checking on
vf 1 MAC 02:52:00:02:01:01, spoof checking on
vf 2 MAC 02:52:00:02:01:02, spoof checking on
```

---

## systemd 持久化

脚本会生成：

```text
x520-sriov-nic1.service
```

并自动执行：

```bash
systemctl enable x520-sriov-nic1.service
```

查看状态：

```bash
systemctl status x520-sriov-nic1.service
```

查看 unit：

```bash
systemctl cat x520-sriov-nic1.service
```

验证 unit 文件：

```bash
systemd-analyze verify /etc/systemd/system/x520-sriov-nic1.service
```

手动启动：

```bash
systemctl start x520-sriov-nic1.service
```

重新执行：

```bash
systemctl restart x520-sriov-nic1.service
```

---

## 为什么不把初始化命令直接写在 ExecStart

早期版本曾使用：

```ini
ExecStart=/bin/bash -c '...'
```

并在其中包含：

```bash
printf -v mac "%s:%02x"
```

但 systemd unit 文件中的 `%` 具有特殊含义，会被当成 specifier 解析。

例如：

```text
%s
```

不会单纯作为 Bash 的 `printf` 格式字符串处理。

这可能导致：

```text
Loaded: bad-setting
```

因此当前版本已经将真正的初始化逻辑拆分到：

```text
/usr/local/sbin/x520-sriov-nic1-init.sh
```

systemd service 只调用该脚本。

这种方式更容易维护，也更不容易受到 systemd 转义规则影响。

---

## 重启后验证

服务器重启以后：

```bash
systemctl status x520-sriov-nic1.service
```

正常情况下应该显示：

```text
Active: active (exited)
```

然后检查 VF：

```bash
ip link show nic1
```

也可以查看：

```bash
cat /sys/class/net/nic1/device/sriov_numvfs
```

例如：

```text
6
```

---

## 查看 VF PCI 设备

可以通过：

```bash
lspci | grep -i ethernet
```

或：

```bash
readlink -f /sys/class/net/nic1/device/virtfn*
```

查看对应 VF 的 PCI 地址。

也可以使用：

```bash
lspci -nnk
```

确认 VF 当前绑定的驱动，例如：

```text
Kernel driver in use: ixgbevf
```

或：

```text
Kernel driver in use: vfio-pci
```

---

## Proxmox VE 中直通 VF

创建 VF 后，可以在 PVE 中将对应 VF PCI 设备添加给虚拟机。

典型路径：

```text
VM
 -> Hardware
 -> Add
 -> PCI Device
```

选择对应 VF 即可。

如果准备调整 VF 数量，请先关闭所有正在使用这些 VF 的虚拟机。

否则脚本会检测到 `/dev/vfio/<group>` 正在被 QEMU 占用，并拒绝删除 VF。

---

## 常见问题

### 1. 提示找不到 sriov_numvfs

例如：

```text
错误：未找到：
/sys/class/net/nic1/device/sriov_numvfs
```

请确认：

- `IFACE` 是否正确
- 网卡是否支持 SR-IOV
- 驱动是否正常加载
- BIOS 是否开启 VT-d / IOMMU
- 系统是否已经启用 IOMMU
- PF 驱动是否支持 SR-IOV

---

### 2. VF 已经从虚拟机移除，但脚本仍提示占用

先确认虚拟机是否已经完全停止。

仅仅从 PVE Hardware 页面删除 PCI Device，并不一定意味着对应 QEMU 进程已经释放 VF。

可以检查：

```bash
ps aux | grep qemu
```

以及：

```bash
ls -l /proc/*/fd/* 2>/dev/null | grep /dev/vfio/
```

---

### 3. VF 绑定 vfio-pci 是否意味着正在使用

不是。

`vfio-pci` 只是驱动绑定状态。

真正是否被虚拟机占用，需要确认是否有进程打开：

```text
/dev/vfio/<IOMMU_GROUP>
```

本脚本就是按照这个逻辑进行检测。

---

### 4. 修改 DEFAULT_VFS 后怎么办

修改：

```bash
DEFAULT_VFS=<数量>
```

然后重新运行：

```bash
./x520-vf.sh
```

选择：

```text
3) 按脚本设定值初始化 VF
```

即可。

脚本会重新生成 systemd 初始化脚本和 service 配置。

---

### 5. 修改 MAC_PREFIX 后怎么办

修改：

```bash
MAC_PREFIX="xx:xx:xx:xx:xx"
```

重新运行脚本并选择：

```text
3) 按脚本设定值初始化 VF
```

新的 MAC 会立即应用，并写入开机初始化脚本。

---

## 删除 systemd 持久化配置

如果不再需要开机自动创建 VF：

```bash
systemctl disable --now x520-sriov-nic1.service
```

删除 service：

```bash
rm -f /etc/systemd/system/x520-sriov-nic1.service
```

删除初始化脚本：

```bash
rm -f /usr/local/sbin/x520-sriov-nic1-init.sh
```

最后：

```bash
systemctl daemon-reload
systemctl reset-failed
```

注意：

删除 systemd 配置不会自动删除当前已经存在的 VF。

如需将当前 VF 数量清零，可以重新执行脚本并选择：

```text
2) VF 数量置 0
```

---

## 安全提示

修改 `sriov_numvfs` 会直接删除并重新创建 VF。

如果某个 VF 正在被虚拟机使用，强制删除可能导致：

- 虚拟机网卡立即掉线
- QEMU 设备异常
- VM 网络中断
- PCI/VFIO 状态异常

因此操作前建议：

1. 关闭使用 VF 的虚拟机
2. 确认 VF 已经释放
3. 再调整 VF 数量

虽然脚本已经增加 VFIO 实际占用检测，但仍建议在生产环境中谨慎操作。

---

## 示例配置

假设：

```text
PF：nic1
VF 数量：6
MAC Prefix：02:52:00:02:01
```

配置：

```bash
DEFAULT_VFS=6
IFACE="nic1"
MAC_PREFIX="02:52:00:02:01"
```

最终得到：

```text
VF0  02:52:00:02:01:00
VF1  02:52:00:02:01:01
VF2  02:52:00:02:01:02
VF3  02:52:00:02:01:03
VF4  02:52:00:02:01:04
VF5  02:52:00:02:01:05
```

对应 systemd：

```text
x520-sriov-nic1.service
```

对应初始化脚本：

```text
/usr/local/sbin/x520-sriov-nic1-init.sh
```

---

## License

可根据你的 GitHub 仓库需求自行选择 License，例如：

- MIT
- Apache-2.0
- GPL-3.0

如果仅作为个人 Homelab 脚本保存，也可以不附加开源许可证。

---

## Disclaimer

本脚本会直接操作 SR-IOV、PCI VF、VFIO 以及 sysfs。

请在理解相关操作影响后使用。

建议首次使用前确认：

```bash
cat /sys/class/net/nic1/device/sriov_totalvfs
cat /sys/class/net/nic1/device/sriov_numvfs
ip link show nic1
```

并确保重要虚拟机已经停止。
