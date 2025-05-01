#!/bin/bash

# 检查 dialog 是否安装
if ! command -v dialog &> /dev/null; then
    echo "错误: 需要 'dialog' 命令，请先安装。" >&2
    echo "例如: sudo apt update && sudo apt install dialog" >&2
    exit 1
fi

# 检查 jq 是否安装
if ! command -v jq &> /dev/null; then
    echo "错误: 需要 'jq' 命令，请先安装。" >&2
    echo "例如: sudo apt update && sudo apt install jq" >&2
    exit 1
fi

# 检查 ss 是否安装 (通常在 iproute2 包中)
if ! command -v ss &> /dev/null; then
    echo "错误: 需要 'ss' 命令 (通常在 'iproute2' 包中)，请先安装。" >&2
    echo "例如: sudo apt update && sudo apt install iproute2" >&2
    exit 1
fi

CONFIG_DIR="/opt/QQ/resources/app/app_launcher/napcat/config"
BASE_NAPCAT_CONFIG="$CONFIG_DIR/napcat.json"
BASE_ONEBOT_CONFIG="$CONFIG_DIR/onebot11.json"

# --- 函数定义 ---



# 正向WS配置





# 函数：获取有效的QQ账号列表
get_qq_accounts() {
    local accounts=()
    # 确保目录存在
    if [[ ! -d "$CONFIG_DIR" ]]; then
        dialog --msgbox "错误：配置目录 '$CONFIG_DIR' 不存在。" 8 50
        return 1
    fi
    shopt -s nullglob # 如果没有匹配的文件，则不报错
    for file in "$CONFIG_DIR"/onebot11_*.json; do
        local filename=$(basename "$file")
        # 提取文件名中的数字部分
        if [[ "$filename" =~ onebot11_([0-9]+)\.json ]]; then
            local qq="${BASH_REMATCH[1]}"
            # 检查QQ号长度是否大于3
            if [[ ${#qq} -gt 3 ]]; then
                accounts+=("$qq")
            fi
        fi
    done
    shopt -u nullglob
    # 返回空格分隔的列表
    echo "${accounts[@]}"
    return 0
}

# 函数：添加新账号
add_account() {
    while true; do
        NEW_QQ=$(dialog --clear --backtitle "添加账号" \
                        --title "输入新QQ账号" \
                        --inputbox "请输入新增的QQ账号（至少4位数字）:" 10 40 \
                        2>&1 >/dev/tty)
        local exit_status=$?
        clear

        # 用户按了取消或ESC
        if [[ $exit_status -ne 0 ]]; then
            dialog --msgbox "添加操作已取消。" 6 40
            return 1 # 表示取消
        fi

        # 验证输入是否为至少4位数字
        if [[ "$NEW_QQ" =~ ^[0-9]{4,}$ ]]; then
            local new_napcat_file="$CONFIG_DIR/napcat_${NEW_QQ}.json"
            local new_onebot_file="$CONFIG_DIR/onebot11_${NEW_QQ}.json"

            # 检查配置文件是否已存在
            if [[ -f "$new_napcat_file" || -f "$new_onebot_file" ]]; then
                 dialog --yesno "账号 $NEW_QQ 的配置文件已存在，是否覆盖？" 8 50 2>&1 >/dev/tty
                 if [[ $? -ne 0 ]]; then # 用户选择 "否"
                     continue # 重新提示输入
                 fi
            fi

            # 检查基础配置文件是否存在
            if [[ ! -f "$BASE_NAPCAT_CONFIG" ]]; then
                dialog --msgbox "错误：基础配置文件 '$BASE_NAPCAT_CONFIG' 不存在。" 8 60
                return 2 # 表示基础文件缺失
            fi
             if [[ ! -f "$BASE_ONEBOT_CONFIG" ]]; then
                dialog --msgbox "错误：基础配置文件 '$BASE_ONEBOT_CONFIG' 不存在。" 8 60
                return 2 # 表示基础文件缺失
            fi

            # 复制文件
            cp "$BASE_NAPCAT_CONFIG" "$new_napcat_file" && \
            cp "$BASE_ONEBOT_CONFIG" "$new_onebot_file"

            if [[ $? -eq 0 ]]; then
                dialog --msgbox "账号 $NEW_QQ 添加成功！\nNapcat 配置: $new_napcat_file\nOneBot 配置: $new_onebot_file" 10 70
                return 0 # 表示成功
            else
                dialog --msgbox "错误：复制文件时出错，请检查权限或磁盘空间。" 8 60
                return 3 # 表示复制失败
            fi
        else
            dialog --msgbox "输入无效！请输入至少4位数字。" 6 40
            # 循环继续，要求重新输入
        fi
    done
}

# 函数：显示网络服务配置菜单 (菜单2)
show_service_menu() {
    local qq_account=$1
    while true; do
        SERVICE_CHOICE=$(dialog --clear --backtitle "网络服务配置" \
                                --title "配置 $qq_account 的网络服务" \
                                --menu "请选择要配置的服务类型:" 15 60 4 \
                                1 "HTTP 服务端 (正向http)" \
                                2 "HTTP 客户端 (反向http)" \
                                3 "WebSocket 服务端 (正向ws)" \
                                4 "WebSocket 客户端 (反向ws)" \
                                2>&1 >/dev/tty)

        local exit_status=$?
        clear

        if [[ $exit_status -ne 0 ]]; then
            # 用户按了取消或ESC，返回到账号选择菜单
            return
        fi

        case "$SERVICE_CHOICE" in
            1)
                dialog --msgbox "将为账号 $qq_account 配置 HTTP 服务端 (正向http) - 功能待实现" 8 60
                # 在这里调用具体的配置函数，例如: configure_http_server "$qq_account"
                ;;
            2)
                dialog --msgbox "将为账号 $qq_account 配置 HTTP 客户端 (反向http) - 功能待实现" 8 60
                # configure_reverse_http_client "$qq_account"
                ;;
            3)
                dialog --msgbox "将为账号 $qq_account 配置 WebSocket 服务端 (正向ws) - 功能待实现" 8 60
                # configure_ws_server "$qq_account"
                ;;
            4)
                dialog --msgbox "将为账号 $qq_account 配置 WebSocket 客户端 (反向ws) - 功能待实现" 8 60
                # configure_reverse_ws_client "$qq_account"
                ;;
            *)
                dialog --msgbox "无效的选择: $SERVICE_CHOICE" 6 40
                ;;
        esac
        # 可以在这里决定是继续显示服务菜单还是返回账号菜单
        # 当前实现是每次选择后都显示提示并停留在服务菜单，按取消返回
    done
}

# --- 主逻辑 ---

# 主循环，显示账号选择菜单 (菜单1)
while true; do
    ACCOUNTS_LIST=($(get_qq_accounts))
    if [[ $? -ne 0 ]]; then # 如果 get_qq_accounts 失败 (例如目录不存在)
        dialog --msgbox "错误：无法获取账号列表，请检查配置目录 '$CONFIG_DIR'。" 8 60
        exit 1
    fi

    MENU_ITEMS=()
    for acc in "${ACCOUNTS_LIST[@]}"; do
        MENU_ITEMS+=("$acc" "配置 $acc")
    done
    MENU_ITEMS+=("ADD" "添加新账号")

    # 计算实际的菜单项数量 (账号数 + 添加项)
    num_entries=$(( ${#ACCOUNTS_LIST[@]} + 1 )) # 移除 local

    # 设置列表的期望显示高度 (例如，最多显示 8 行)
    list_height=$num_entries # 移除 local
    [[ $list_height -gt 8 ]] && list_height=8
    [[ $list_height -lt 1 ]] && list_height=1 # 确保至少为1

    # 计算对话框的总高度：列表高度 + 额外空间 (约 7 行)
    menu_height=$(( list_height + 7 )) # 移除 local
    [[ $menu_height -lt 10 ]] && menu_height=10 # 确保最小总高度


    CHOICE=$(dialog --clear --backtitle "QQ账号管理" \
                    --title "选择QQ账号" \
                    --menu "请选择一个账号进行配置，或添加新账号:" \
                    "$menu_height" 55 "$list_height" \
                    "${MENU_ITEMS[@]}" \
                    2>&1 >/dev/tty)

    exit_status=$?
    clear

    # 用户按了取消或ESC，退出脚本
    if [[ $exit_status -ne 0 ]]; then
        echo "操作已取消或退出。"
        break
    fi

    case "$CHOICE" in
        ADD)
            add_account
            # 添加后，循环会自动重新开始，刷新列表
            ;;
        *)
            # 检查选择的是否是有效的账号
            is_valid_account=false
            for acc in "${ACCOUNTS_LIST[@]}"; do
                if [[ "$CHOICE" == "$acc" ]]; then
                    is_valid_account=true
                    break
                fi
            done

            if $is_valid_account; then
                # 进入菜单2
                show_service_menu "$CHOICE"
                # 从菜单2返回后，循环继续，回到账号选择菜单
            else
                 # 这通常不应该发生，因为dialog只返回菜单中的有效项
                 dialog --msgbox "出现意外错误，无效的选择: $CHOICE" 6 40
            fi
            ;;
    esac
done

# 清理屏幕并退出