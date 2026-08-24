#!/bin/bash

set -e

echo "======================================"
echo " Linux VM 串口控制台一键启用脚本"
echo " 支持: Ubuntu 25.04 / CentOS 7.9 / Debian 13"
echo "======================================"
echo

if [ ! -f /etc/os-release ]; then
  echo "无法识别系统发行版"
  exit 1
fi

source /etc/os-release

AUTO_ID="$ID"
AUTO_VER="$VERSION_ID"

echo "自动识别系统: $NAME $VERSION_ID"
echo
echo "请选择你的系统:"
echo "1) Ubuntu Server 25.04"
echo "2) CentOS 7.9"
echo "3) Debian 13"
echo "4) 使用自动识别结果: $NAME $VERSION_ID"
echo
read -p "请输入选择 [1-4]: " CHOICE

case "$CHOICE" in
  1) SYS="ubuntu" ;;
  2) SYS="centos7" ;;
  3) SYS="debian" ;;
  4)
    if [[ "$AUTO_ID" == "ubuntu" ]]; then
      SYS="ubuntu"
    elif [[ "$AUTO_ID" == "centos" || "$AUTO_ID" == "rhel" ]]; then
      SYS="centos7"
    elif [[ "$AUTO_ID" == "debian" ]]; then
      SYS="debian"
    else
      echo "自动识别失败，请手动选择"
      exit 1
    fi
    ;;
  *)
    echo "无效选择"
    exit 1
    ;;
esac

echo
echo "目标系统: $SYS"
read -p "确认对该系统启用串口控制台 ttyS0？[y/N]: " CONFIRM
[[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]] && exit 0

echo
echo "开始配置..."

# 判断启动模式
if [ -d /sys/firmware/efi ]; then
  BOOTMODE="uefi"
else
  BOOTMODE="bios"
fi

echo "启动模式: $BOOTMODE"

GRUB_FILE="/etc/default/grub"

backup_file() {
  cp "$1" "$1.bak.$(date +%F_%H-%M-%S)"
}

backup_file "$GRUB_FILE"

append_console_param() {
  KEY="$1"

  if grep -q "^$KEY=" "$GRUB_FILE"; then
    CURRENT=$(grep "^$KEY=" "$GRUB_FILE" | sed 's/^[^"]*"\(.*\)"/\1/')
    if [[ "$CURRENT" != *"console=ttyS0"* ]]; then
      sed -i "s|^$KEY=\"|$KEY=\"$CURRENT |" "$GRUB_FILE"
      sed -i "s|\"$| console=tty0 console=ttyS0,115200n8\"|" "$GRUB_FILE"
    fi
  else
    echo "$KEY=\"console=tty0 console=ttyS0,115200n8\"" >> "$GRUB_FILE"
  fi
}

case "$SYS" in
  ubuntu|debian)
    append_console_param "GRUB_CMDLINE_LINUX_DEFAULT"
    ;;
  centos7)
    append_console_param "GRUB_CMDLINE_LINUX"
    ;;
esac

echo "GRUB 参数已更新"

# 生成 grub.cfg
if [[ "$SYS" == "ubuntu" || "$SYS" == "debian" ]]; then
  update-grub
elif [[ "$SYS" == "centos7" ]]; then
  if [[ "$BOOTMODE" == "uefi" ]]; then
    grub2-mkconfig -o /boot/efi/EFI/centos/grub.cfg
  else
    grub2-mkconfig -o /boot/grub2/grub.cfg
  fi
fi

# 启用串口登录
systemctl enable serial-getty@ttyS0.service
systemctl start serial-getty@ttyS0.service

echo
echo "======================================"
echo " 串口控制台配置完成"
echo "======================================"
echo
echo "已备份原 grub 配置为:"
ls -1 /etc/default/grub.bak.* 2>/dev/null | tail -n 1
echo
echo "重启后请在 PVE Console -> Serial0 查看效果"
echo

read -p "是否现在重启系统？[y/N]: " REBOOT
if [[ "$REBOOT" == "y" || "$REBOOT" == "Y" ]]; then
  reboot
fi
