#!/bin/sh

###########################################
# Docker Image Transfer Tool
# Author: ChatGPT
###########################################

set -e

# 颜色
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
BLUE="\033[36m"
NC="\033[0m"

msg() {
    printf "%b%s%b\n" "$GREEN" "$1" "$NC"
}

warn() {
    printf "%b%s%b\n" "$YELLOW" "$1" "$NC"
}

err() {
    printf "%b%s%b\n" "$RED" "$1" "$NC"
}

###########################################
# 导入
###########################################
import_image() {

    FILE="$1"

    if [ ! -f "$FILE" ]; then
        err "文件不存在：$FILE"
        exit 1
    fi

    msg "开始导入镜像..."

    case "$FILE" in
        *.gz)
            gzip -dc "$FILE" | docker load
            ;;
        *)
            docker load -i "$FILE"
            ;;
    esac

    msg "导入完成！"

    echo
    docker images
}

###########################################
# 导出
###########################################
export_image() {

    echo
    read -p "请输入镜像名称（例如 nginx:latest）： " IMAGE

    if [ -z "$IMAGE" ]; then
        err "镜像不能为空"
        exit 1
    fi

    msg "拉取镜像..."

    docker pull "$IMAGE"

    TAG=$(echo "$IMAGE" | awk -F: '{print $2}')

    if [ -z "$TAG" ]; then
        TAG="latest"
    fi

    REPO=$(echo "$IMAGE" | awk -F: '{print $1}')

    SAFE_NAME=$(echo "$REPO" | tr '/:' '_')

    FILE="${SAFE_NAME}_${TAG}.tar.gz"

    msg "正在导出..."

    docker save "$IMAGE" | gzip > "$FILE"

    echo
    msg "完成！"

    echo "文件：$(pwd)/$FILE"

    echo
    docker image inspect "$IMAGE" \
        --format 'Repository={{index .RepoTags 0}}
ImageID={{.Id}}
Created={{.Created}}'

}

###########################################
# 从 compose 文件导出所有镜像
###########################################
compose_export() {

    COMPOSE_FILE="$1"

    if [ ! -f "$COMPOSE_FILE" ]; then
        err "文件不存在：$COMPOSE_FILE"
        exit 1
    fi

    case "$COMPOSE_FILE" in
        *.yml|*.yaml) ;;
        *)
            err "仅支持 .yml / .yaml 文件"
            exit 1
            ;;
    esac

    IMAGES=$(grep -E '^[[:space:]]*image:[[:space:]]*' "$COMPOSE_FILE" \
        | sed -E 's/^[[:space:]]*image:[[:space:]]*//' \
        | sed -E 's/[[:space:]]*#.*$//' \
        | sed -E "s/^[\"']//; s/[\"']\$//" \
        | sed -E 's/[[:space:]]+$//' \
        | grep -v '^$' \
        | sort -u)

    if [ -z "$IMAGES" ]; then
        err "未在 $COMPOSE_FILE 中找到 image 字段"
        exit 1
    fi

    msg "从 compose 文件中解析到以下镜像："
    echo "$IMAGES"
    echo

    for IMG in $IMAGES; do
        msg "拉取镜像：$IMG"
        docker pull "$IMG"
    done

    BASE_NAME=$(basename "$COMPOSE_FILE")
    BASE_NAME=${BASE_NAME%.*}
    SAFE_NAME=$(echo "$BASE_NAME" | tr '/:' '_')
    OUT_FILE="${SAFE_NAME}_images.tar.gz"

    msg "正在打包..."

    docker save $IMAGES | gzip > "$OUT_FILE"

    echo
    msg "完成！"

    echo "文件：$(pwd)/$OUT_FILE"

    echo
    for IMG in $IMAGES; do
        docker image inspect "$IMG" \
            --format 'Repository={{index .RepoTags 0}}
ImageID={{.Id}}
Created={{.Created}}'
        echo
    done
}

###########################################
# 参数模式：-f compose.yml/yaml
###########################################
if [ "$1" = "-f" ]; then

    if [ -z "$2" ]; then
        err "用法：$0 -f docker-compose.yml"
        exit 1
    fi

    compose_export "$2"
    exit 0
fi

###########################################
# 菜单
###########################################

echo
echo "=============================="
echo " Docker 镜像离线迁移工具"
echo "=============================="
echo
echo "1. 下载并打包镜像"
echo "2. 解压导入镜像"
echo

read -p "请选择（1/2）： " CHOICE

case "$CHOICE" in

1)
    export_image
    ;;

2)

    echo
    read -p "请输入 tar.gz 文件路径： " FILE

    import_image "$FILE"
    ;;

*)

    err "输入错误"

    ;;

esac