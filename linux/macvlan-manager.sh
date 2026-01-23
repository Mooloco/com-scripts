#!/bin/bash
# CentOS7 Macvlan 管理脚本

# 自动加载 macvlan 模块
echo ">>> 检查 macvlan 模块..."
if ! lsmod | grep -q macvlan; then
    echo "未加载 macvlan 模块，正在加载..."
    modprobe macvlan
    if [ $? -eq 0 ]; then
        echo "macvlan 模块已成功加载"
    else
        echo "加载 macvlan 模块失败，请检查内核是否支持"
        exit 1
    fi
else
    echo "macvlan 模块已加载"
fi

# 注意事项
cat <<EOF

================ 注意事项 ================
1. Macvlan 接口与宿主机默认不能互通
2. 请确保目标物理网卡已连接网络
3. DNS 默认为 223.5.5.5
4. 子网掩码默认 255.255.255.0
==========================================

EOF

# 选择物理网卡
function select_parent_if() {
    echo ">>> 检测可用物理网卡..."
    IFACES=($(ls /sys/class/net | grep -Ev '^(lo|docker.*|veth.*|macvlan.*|virbr.*)$'))
    if [ ${#IFACES[@]} -eq 0 ]; then
        echo "未找到可用物理网卡"
        exit 1
    fi

    echo "可用物理网卡列表："
    for i in "${!IFACES[@]}"; do
        echo "$((i+1))) ${IFACES[$i]}"
    done

    while true; do
        read -p "请选择物理网卡编号 [1-${#IFACES[@]}]: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ $choice -ge 1 ] && [ $choice -le ${#IFACES[@]} ]; then
            PARENT_IF=${IFACES[$((choice-1))]}
            echo "已选择物理网卡: $PARENT_IF"
            break
        else
            echo "无效输入，请重新选择"
        fi
    done
}

# 获取用户输入函数
function get_network_config() {
    select_parent_if
    read -p "请输入新建 macvlan 接口名称 (例如 macvlan0): " VLAN_IF
    echo "请选择 macvlan 模式 (回车默认 bridge):"
    echo "1) bridge"
    echo "2) private"
    echo "3) vepa"
    echo "4) passthru"
    read -p "请输入选项 [1-4]: " MODE_CHOICE
    case $MODE_CHOICE in
        2) VLAN_MODE="private" ;;
        3) VLAN_MODE="vepa" ;;
        4) VLAN_MODE="passthru" ;;
        *) VLAN_MODE="bridge" ;;
    esac
    read -p "请输入 IP 地址 (例如 192.168.1.100): " IP_ADDR
    read -p "请输入子网掩码 (默认 24 请使用CIDR格式): " NETMASK
    NETMASK=${NETMASK:-255.255.255.0}
    read -p "请输入网关 (可留空): " GATEWAY
    read -p "请输入 DNS (默认 223.5.5.5): " DNS
    DNS=${DNS:-223.5.5.5}
}

# 使用 ip 命令创建 macvlan
function create_with_ip() {
    get_network_config
    echo ">>> 正在创建 macvlan 接口 $VLAN_IF (模式: $VLAN_MODE)..."
    ip link add $VLAN_IF link $PARENT_IF type macvlan mode $VLAN_MODE
    ip addr add $IP_ADDR/$NETMASK dev $VLAN_IF
    ip link set $VLAN_IF up
    [ -n "$GATEWAY" ] && ip route add default via $GATEWAY dev $VLAN_IF
    echo "nameserver $DNS" > /etc/resolv.conf
    echo ">>> 创建完成！"
    show_summary
}

# 使用 nmcli 命令创建 macvlan
function create_with_nmcli() {
    get_network_config
    echo ">>> 正在使用 nmcli 创建 macvlan 接口 $VLAN_IF (模式: $VLAN_MODE)..."
    nmcli connection add type macvlan ifname $VLAN_IF dev $PARENT_IF mode $VLAN_MODE ip4 $IP_ADDR/$NETMASK gw4 $GATEWAY
    nmcli connection modify $VLAN_IF ipv4.dns "$DNS"
    nmcli connection up $VLAN_IF
    echo ">>> 创建完成！"
    show_summary
}

# 删除所有 macvlan 接口
function delete_all_macvlan() {
    echo ">>> 正在删除所有 macvlan 接口..."
    for IF in $(ip -o link show | awk -F': ' '{print $2}' | grep macvlan); do
        ip link delete $IF
        echo "已删除接口: $IF"
    done
    echo ">>> 所有 macvlan 接口已删除"
}

# 总结信息
function show_summary() {
    echo
    echo "================ 配置信息总结 ================"
    echo "物理网卡:   $PARENT_IF"
    echo "macvlan接口: $VLAN_IF"
    echo "模式:       $VLAN_MODE"
    echo "IP 地址:    $IP_ADDR"
    echo "子网掩码:   $NETMASK"
    echo "网关:       ${GATEWAY:-无}"
    echo "DNS:        $DNS"
    echo "============================================"
}

# 菜单
while true; do
    echo
    echo "========= Macvlan 管理菜单 ========="
    echo "1) 使用 ip 创建 macvlan"
    echo "2) 使用 nmcli 创建 macvlan"
    echo "3) 删除所有 macvlan 接口"
    echo "4) 退出"
    echo "==================================="
    read -p "请选择操作 [1-4]: " choice

    case $choice in
        1) create_with_ip ;;
        2) create_with_nmcli ;;
        3) delete_all_macvlan ;;
        4) echo "退出程序"; exit 0 ;;
        *) echo "无效选项，请重新输入" ;;
    esac
done
