#!/bin/bash

# ============================================================
# Intel X520 SR-IOV VF 管理脚本
#
# 【常用修改项】
#
# 1) 默认初始化 VF 数量：
#    DEFAULT_VFS=6
#
# 2) X520 物理接口：
#    IFACE="nic1"
#
# 3) VF 固定 MAC 前 5 字节：
#    MAC_PREFIX="02:52:00:02:01"
#
#    最后 1 字节由 VF 编号自动生成：
#      VF0 -> 02:52:00:02:01:00
#      VF1 -> 02:52:00:02:01:01
#      ...
#
#    02 开头为本地管理 MAC（Locally Administered Address）。
#
# 功能：
#   1. 保持当前数量并增加 1 个 VF
#   2. VF 数量置 0
#   3. 按 DEFAULT_VFS 重新初始化
#   4. 退出
#   5. 自动为所有 VF 设置固定 MAC
#   6. 默认开启 spoof checking
#   7. 检测 VFIO 设备组的实际进程占用，避免删除正在使用的 VF
#   8. 自动生成独立的开机初始化脚本
#   9. 自动生成 systemd 服务，重启后恢复 VF 数量和固定 MAC
#
# systemd 结构：
#   /usr/local/sbin/x520-sriov-nic1-init.sh
#       ↑ 真正执行 VF 初始化和 MAC 配置
#
#   /etc/systemd/system/x520-sriov-nic1.service
#       ↑ 只负责调用上面的初始化脚本
# ============================================================

DEFAULT_VFS=6
IFACE="nic1"
MAC_PREFIX="02:52:00:02:01"

SYSFS="/sys/class/net/${IFACE}/device/sriov_numvfs"
TOTAL_SYSFS="/sys/class/net/${IFACE}/device/sriov_totalvfs"

SERVICE_NAME="x520-sriov-${IFACE}.service"
SERVICE="/etc/systemd/system/${SERVICE_NAME}"
INIT_SCRIPT="/usr/local/sbin/x520-sriov-${IFACE}-init.sh"


# ------------------------------------------------------------
# root 检查
# ------------------------------------------------------------

if [[ $EUID -ne 0 ]]; then
    echo "错误：请使用 root 权限运行此脚本。"
    exit 1
fi


# ------------------------------------------------------------
# 接口检查
# ------------------------------------------------------------

if [[ ! -e "$SYSFS" ]]; then
    echo "错误：未找到："
    echo "$SYSFS"
    echo
    echo "请确认接口 ${IFACE} 存在，并且支持 SR-IOV。"
    exit 1
fi


# ------------------------------------------------------------
# 检查 MAC_PREFIX 格式
# 必须正好为 5 个十六进制字节
# ------------------------------------------------------------

if [[ ! "$MAC_PREFIX" =~ ^([0-9A-Fa-f]{2}:){4}[0-9A-Fa-f]{2}$ ]]; then
    echo "错误：MAC_PREFIX 格式不正确：${MAC_PREFIX}"
    echo "正确示例：02:52:00:02:01"
    exit 1
fi


# ------------------------------------------------------------
# 获取 VF PCI 地址
# ------------------------------------------------------------

get_vf_pci_devices() {

    local DEVICE_PATH
    local VF

    DEVICE_PATH=$(readlink -f "/sys/class/net/${IFACE}/device")

    for VF in "$DEVICE_PATH"/virtfn*; do
        [[ -e "$VF" ]] || continue
        basename "$(readlink -f "$VF")"
    done
}


# ------------------------------------------------------------
# 检测 VFIO 组是否被进程持有。仅绑定 vfio-pci 不代表正在使用。
# ------------------------------------------------------------

check_vf_in_use() {

    local PCI DRIVER GROUP FD PID TARGET COMM
    local -A CHECKED_GROUPS=()

    while read -r PCI; do

        [[ -z "$PCI" ]] && continue

        DRIVER=$(basename "$(readlink -f "/sys/bus/pci/devices/${PCI}/driver" 2>/dev/null)")

        if [[ "$DRIVER" == "vfio-pci" ]]; then

            GROUP=$(basename "$(readlink -f "/sys/bus/pci/devices/${PCI}/iommu_group" 2>/dev/null)")
            if [[ ! "$GROUP" =~ ^[0-9]+$ ]]; then
                echo "错误：无法确认 ${PCI} 的 IOMMU 组，停止操作。" >&2
                return 1
            fi

            [[ -n "${CHECKED_GROUPS[$GROUP]+x}" ]] && continue
            CHECKED_GROUPS[$GROUP]=1

            for FD in /proc/[0-9]*/fd/*; do
                [[ -e "$FD" ]] || continue
                TARGET=$(readlink "$FD" 2>/dev/null) || continue

                if [[ "$TARGET" == "/dev/vfio/${GROUP}" ]]; then
                    PID=${FD#/proc/}
                    PID=${PID%%/*}
                    COMM=$(cat "/proc/${PID}/comm" 2>/dev/null || printf 'unknown')

                    echo "VF ${PCI} 所在 IOMMU 组 ${GROUP} 正被进程 ${PID} (${COMM}) 使用。" >&2
                    echo "请先停止使用该 VF 的虚拟机，然后重试。" >&2
                    return 1
                fi
            done
        fi

    done < <(get_vf_pci_devices)

    return 0
}


# ------------------------------------------------------------
# 删除 VF 前解绑空闲的 vfio-pci VF
# ------------------------------------------------------------

unbind_idle_vfs() {

    local PCI DRIVER

    check_vf_in_use || return 1

    while read -r PCI; do

        [[ -n "$PCI" ]] || continue

        DRIVER=$(basename "$(readlink -f "/sys/bus/pci/devices/${PCI}/driver" 2>/dev/null)")

        if [[ "$DRIVER" == "vfio-pci" ]]; then

            check_vf_in_use || return 1

            echo "$PCI" > /sys/bus/pci/drivers/vfio-pci/unbind || return 1
            echo "已解绑空闲 VF：${PCI}"
        fi

    done < <(get_vf_pci_devices)
}


# ------------------------------------------------------------
# 根据 VF 编号生成固定 MAC
# ------------------------------------------------------------

get_vf_mac() {

    local VF_INDEX="$1"

    if (( VF_INDEX < 0 || VF_INDEX > 255 )); then
        return 1
    fi

    printf '%s:%02x' "$MAC_PREFIX" "$VF_INDEX"
}


# ------------------------------------------------------------
# 为当前所有 VF 设置固定 MAC
# ------------------------------------------------------------

apply_vf_macs() {

    local COUNT
    local I
    local MAC

    COUNT=$(cat "$SYSFS")

    if (( COUNT == 0 )); then
        return 0
    fi

    echo
    echo "正在配置 VF 固定 MAC："

    for ((I=0; I<COUNT; I++)); do

        MAC=$(get_vf_mac "$I") || {
            echo "错误：无法生成 VF${I} 的 MAC。"
            return 1
        }

        if ! ip link set dev "$IFACE" vf "$I" mac "$MAC" spoofchk on; then
            echo
            echo "错误：设置 VF${I} MAC 失败：${MAC}"
            return 1
        fi

        echo "  VF${I} -> ${MAC}  (spoofchk on)"
    done

    return 0
}


# ------------------------------------------------------------
# 生成独立的 systemd 开机初始化脚本
# ------------------------------------------------------------

create_init_script() {

    local COUNT="$1"

    cat > "$INIT_SCRIPT" <<EOF
#!/bin/bash
set -euo pipefail

IFACE="${IFACE}"
COUNT="${COUNT}"
MAC_PREFIX="${MAC_PREFIX}"
SYSFS="${SYSFS}"

if [[ ! -e "\$SYSFS" ]]; then
    echo "错误：未找到 \$SYSFS" >&2
    exit 1
fi

current=\$(cat "\$SYSFS")

# VF 数量与目标不一致时，先清零，再重新创建。
if [[ "\$current" != "\$COUNT" ]]; then

    if (( current > 0 )); then
        echo 0 > "\$SYSFS"
    fi

    if (( COUNT > 0 )); then
        echo "\$COUNT" > "\$SYSFS"
    fi
fi

# 无论是否重新创建，都重新写入固定 MAC。
if (( COUNT > 0 )); then

    for ((i=0; i<COUNT; i++)); do
        printf -v mac '%s:%02x' "\$MAC_PREFIX" "\$i"
        /usr/sbin/ip link set dev "\$IFACE" vf "\$i" mac "\$mac" spoofchk on
    done
fi
EOF

    chmod 0755 "$INIT_SCRIPT"
}


# ------------------------------------------------------------
# 生成持久化 systemd 服务
#
# 注意：
#   service 不再包含长 Bash。
#   ExecStart 只调用独立初始化脚本。
# ------------------------------------------------------------

create_service() {

    local COUNT="$1"

    if ! create_init_script "$COUNT"; then
        echo
        echo "错误：无法生成开机初始化脚本：${INIT_SCRIPT}"
        return 1
    fi

    cat > "$SERVICE" <<EOF
[Unit]
Description=Configure Intel X520 SR-IOV VFs and MAC addresses for ${IFACE}
After=systemd-modules-load.service
Before=pve-guests.service

[Service]
Type=oneshot
ExecStart=${INIT_SCRIPT}
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload

    if ! systemctl enable "$SERVICE_NAME" >/dev/null 2>&1; then
        echo
        echo "警告：无法启用 systemd 服务 ${SERVICE_NAME}。"
        return 1
    fi

    return 0
}


# ------------------------------------------------------------
# 设置 VF 数量
# 会自动先清零，再创建目标数量
# 创建完成后立即设置固定 MAC
# ------------------------------------------------------------

set_vf_count() {

    local TARGET="$1"
    local CURRENT_NOW

    CURRENT_NOW=$(cat "$SYSFS")

    if (( TARGET > TOTAL )); then
        echo
        echo "错误：目标 VF 数量 ${TARGET} 超过硬件最大值 ${TOTAL}。"
        return 1
    fi

    if (( TARGET > 256 )); then
        echo
        echo "错误：当前 MAC 自动编号方案最多支持 256 个 VF。"
        return 1
    fi

    if (( CURRENT_NOW > 0 )); then

        unbind_idle_vfs || return 1

        if ! echo 0 > "$SYSFS"; then
            echo
            echo "错误：无法删除当前 VF。"
            return 1
        fi
    fi

    if (( TARGET > 0 )); then

        if ! echo "$TARGET" > "$SYSFS"; then
            echo
            echo "错误：创建 ${TARGET} 个 VF 失败。"
            return 1
        fi

        if ! apply_vf_macs; then
            return 1
        fi
    fi

    return 0
}


# ------------------------------------------------------------
# 显示当前 VF MAC
# ------------------------------------------------------------

show_vf_macs() {

    local COUNT
    local I
    local MAC

    COUNT=$(cat "$SYSFS")

    if (( COUNT == 0 )); then
        return 0
    fi

    echo
    echo "计划固定 MAC："

    for ((I=0; I<COUNT; I++)); do
        MAC=$(get_vf_mac "$I")
        echo "  VF${I} -> ${MAC}"
    done
}


# ------------------------------------------------------------
# 获取当前状态
# ------------------------------------------------------------

CURRENT=$(cat "$SYSFS")
TOTAL=$(cat "$TOTAL_SYSFS")


echo
echo "================================================"
echo " Intel X520 SR-IOV VF 管理工具"
echo "================================================"
echo
echo "接口：${IFACE}"
echo "当前 VF 数量：${CURRENT}"
echo "脚本默认 VF 数量：${DEFAULT_VFS}"
echo "硬件最大 VF 数量：${TOTAL}"
echo "固定 MAC 前缀：${MAC_PREFIX}"
echo "开机初始化脚本：${INIT_SCRIPT}"
echo "systemd 服务：${SERVICE_NAME}"
echo
echo "1) 保持当前数量并增加 1 个 VF"
echo "2) VF 数量置 0"
echo "3) 按脚本设定值初始化 VF"
echo "   当前设定值：${DEFAULT_VFS}"
echo "   将执行：当前 VF → 0 → ${DEFAULT_VFS}"
echo "   并重新设置全部 VF 固定 MAC"
echo "4) 退出"
echo

read -rp "请选择 [1-4]: " CHOICE


case "$CHOICE" in

    1)

        NEW=$((CURRENT + 1))

        if (( NEW > TOTAL )); then
            echo
            echo "错误：已经达到硬件最大 VF 数量 ${TOTAL}。"
            exit 1
        fi

        if ! check_vf_in_use; then
            exit 1
        fi

        echo
        echo "准备调整 VF："
        echo
        echo "当前：${CURRENT}"
        echo "目标：${NEW}"
        echo

        if (( CURRENT > 0 )); then
            echo "实际执行过程："
            echo
            echo "${CURRENT} → 0 → ${NEW}"
            echo
            echo "注意：现有 VF 会被重新创建，并重新写入固定 MAC。"
            echo
        fi

        read -rp "确认继续？[y/N]: " CONFIRM

        if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
            echo "已取消。"
            exit 0
        fi

        if ! set_vf_count "$NEW"; then
            exit 1
        fi

        if ! create_service "$NEW"; then
            exit 1
        fi

        echo
        echo "================================================"
        echo "操作成功"
        echo "================================================"
        echo
        echo "当前 VF 数量：$(cat "$SYSFS")"
        echo "重启后 VF 数量：${NEW}"
        show_vf_macs
        ;;


    2)

        if ! check_vf_in_use; then
            exit 1
        fi

        echo
        echo "准备将 ${IFACE} 的 VF 数量置 0。"
        echo

        read -rp "确认继续？[y/N]: " CONFIRM

        if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
            echo "已取消。"
            exit 0
        fi

        if ! set_vf_count 0; then
            exit 1
        fi

        if ! create_service 0; then
            exit 1
        fi

        echo
        echo "================================================"
        echo "操作成功"
        echo "================================================"
        echo
        echo "当前 VF 数量：0"
        echo "重启后 VF 数量：0"
        ;;


    3)

        if ! check_vf_in_use; then
            exit 1
        fi

        echo
        echo "准备按脚本设定值初始化 ${IFACE}。"
        echo
        echo "当前 VF 数量：$(cat "$SYSFS")"
        echo "初始化 VF 数量：${DEFAULT_VFS}"
        echo
        echo "执行过程："
        echo
        echo "$(cat "$SYSFS") → 0 → ${DEFAULT_VFS}"
        echo
        echo "VF 创建完成后会自动写入："

        for ((I=0; I<DEFAULT_VFS; I++)); do
            printf '  VF%d -> %s:%02x\n' "$I" "$MAC_PREFIX" "$I"
        done

        echo

        read -rp "确认初始化？[y/N]: " CONFIRM

        if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
            echo "已取消。"
            exit 0
        fi

        if ! set_vf_count "$DEFAULT_VFS"; then
            exit 1
        fi

        if ! create_service "$DEFAULT_VFS"; then
            exit 1
        fi

        echo
        echo "================================================"
        echo "初始化完成"
        echo "================================================"
        echo
        echo "当前 VF 数量：$(cat "$SYSFS")"
        echo "重启后 VF 数量：${DEFAULT_VFS}"
        show_vf_macs
        ;;


    4)

        echo
        echo "退出。"
        exit 0
        ;;


    *)

        echo
        echo "错误：无效选项。"
        exit 1
        ;;

esac
