#!/bin/bash
#
# 交互式菜单脚本生成器
#

echo "===== 菜单脚本生成器 ====="
read -p "请输入菜单标题: " MENU_TITLE

# 存放选项
OPTIONS=()
INDEX=1

# 输入菜单项
while true; do
    read -p "请输入第 $INDEX 个选项（回车直接结束输入）: " opt
    if [[ -z "$opt" ]]; then
        break
    fi
    OPTIONS+=("$opt")
    INDEX=$((INDEX+1))
done

# 设置函数名前缀
read -p "请输入函数名前缀（默认: option）: " FUNC_PREFIX
FUNC_PREFIX=${FUNC_PREFIX:-option}

# 生成脚本
OUTPUT="generated_menu.sh"
{
    echo "#!/bin/bash"
    echo "# 自动生成的菜单脚本"
    echo
    # 生成函数框架
    for i in "${!OPTIONS[@]}"; do
        fname="${FUNC_PREFIX}$((i+1))"
        echo "${fname}() {"
        echo "    echo \"执行: ${OPTIONS[$i]}\""
        echo "    # TODO: 在这里写功能代码"
        echo "}"
        echo
    done

    # 生成菜单循环
    echo "while true; do"
    echo "    echo \"==== ${MENU_TITLE} ====\""
    for i in "${!OPTIONS[@]}"; do
        echo "    echo \"$((i+1))) ${OPTIONS[$i]}\""
    done
    echo "    echo \"0) 退出\""
    echo "    read -p \"请输入选项 [0-${#OPTIONS[@]}]: \" choice"
    echo
    echo "    case \$choice in"
    for i in "${!OPTIONS[@]}"; do
        fname="${FUNC_PREFIX}$((i+1))"
        echo "        $((i+1))) $fname ;;"
    done
    echo "        0) echo \"退出\"; break ;;"
    echo "        *) echo \"无效选项\" ;;"
    echo "    esac"
    echo "done"
} > "$OUTPUT"

chmod +x "$OUTPUT"
echo "✅ 菜单脚本已生成: $OUTPUT"

