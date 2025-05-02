#!/bin/bash


# --- 配置目录 ---
# 与 Config.sh 保持一致
CONFIG_DIR="/opt/QQ/resources/app/app_launcher/napcat/config"
# 获取当前脚本所在的目录，用于调用 Config.sh
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
CONFIG_SCRIPT="$SCRIPT_DIR/Config.sh"


if [[ $EUID -ne 0 ]]; then
   # 尝试非交互式 sudo，看是否能直接成功 (例如，已缓存密码或 NOPASSWD)
   if sudo -n true &> /dev/null; then
       # 可以非交互式 sudo，直接重新执行 (无提示)
       sudo "$0" "$@"
       exit $? # 退出当前非 root 进程, 传递 sudo 的退出码
   else
       # 非交互式 sudo 失败，需要密码或权限不足
       # 现在显示提示信息
       if command -v dialog &> /dev/null; then
           # 使用 dialog 提示
           dialog --colors --title "需要权限" --msgbox "${FG_YELLOW}此脚本需要 root 权限来修改 '${CONFIG_DIR}' 中的文件。\n\n将通过 sudo 请求密码以获取权限。${RESET}" 10 60 2>&1 >/dev/tty
           clear
       else
           # dialog 不可用时的备用 echo 提示
           echo "提示: 此脚本需要 root 权限才能修改位于 '${CONFIG_DIR}' 的配置文件。" >&2
           echo "将通过 sudo 请求密码以获取权限..." >&2
       fi

       # 现在尝试交互式 sudo，这会提示输入密码
       sudo "$0" "$@"
       exit $? # 退出当前非 root 进程, 传递 sudo 的退出码
   fi
fi

# 检查 dialog 是否安装
if ! command -v dialog &> /dev/null; then
    echo -e "${ANSI_RED}错误: 需要 'dialog' 命令，请先安装。${ANSI_RESET}" >&2
    echo "例如: sudo apt update && sudo apt install dialog" >&2
    exit 1
fi

# 检查 jq 是否安装 (用于读取配置)
if ! command -v jq &> /dev/null; then
    echo -e "${ANSI_RED}错误: 需要 'jq' 命令，请先安装。${ANSI_RESET}" >&2
    echo "例如: sudo apt update && sudo apt install jq" >&2
    exit 1
fi



# --- ANSI 颜色定义 (使用 dialog --colors 的简化代码) ---
# 注意：dialog --colors 使用 \Z 代替 \e[ ，数字代表颜色/属性
RESET='\Zn'      # 重置为正常
BOLD='\Zb'       # 切换粗体

# 前景色
FG_BLACK='\Z0'
FG_RED='\Z1'
FG_GREEN='\Z2'
FG_YELLOW='\Z3'
FG_BLUE='\Z4'
FG_MAGENTA='\Z5'
FG_CYAN='\Z6'
FG_WHITE='\Z7'
# --- ANSI 颜色定义 (用于 echo -e) ---
ANSI_RESET='\e[0m'
ANSI_BOLD='\e[1m'
ANSI_RED='\e[31m'
ANSI_GREEN='\e[32m'
ANSI_YELLOW='\e[33m'
ANSI_BLUE='\e[34m'
ANSI_MAGENTA='\e[35m'
ANSI_CYAN='\e[36m'
ANSI_WHITE='\e[37m'
# --- 函数定义 ---

# 函数：获取有效的QQ账号列表 (改编自 Config.sh)
get_qq_accounts() {
    local accounts=()
    # 确保目录存在
    if [[ ! -d "$CONFIG_DIR" ]]; then
        # 不直接显示 dialog，而是返回错误，由主循环处理
        echo -e "${FG_RED}ERROR: Config directory not found${RESET}" >&2 # 添加颜色
        return 1
    fi
    if [[ ! -d "$CONFIG_DIR" ]]; then
        # 不直接显示 dialog，而是返回错误，由主循环处理
        echo "ERROR: Config directory not found" >&2
        return 1
    fi
    shopt -s nullglob # 如果没有匹配的文件，则不报错
    for file in "$CONFIG_DIR"/onebot11_*.json; do
        local filename=$(basename "$file")
        # 提取文件名中的数字部分
        if [[ "$filename" =~ onebot11_([0-9]+)\.json ]]; then
            local qq="${BASH_REMATCH[1]}"
            # 检查QQ号长度是否大于3 (基本有效性检查)
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

# 函数：获取 Napcat 状态 (占位符 - 需要具体实现)
# 您需要根据实际情况修改此函数来检查 Napcat 是否正在运行
# 例如，检查进程名、PID 文件或监听端口
get_napcat_status() {
    local pid_file="/var/run/napcat.pid"
    local pid=""
    local cmdline=""
    local qq_account=""
    if [[ ! -f "$pid_file" ]] || [[ ! -r "$pid_file" ]]; then
        echo -e "${FG_YELLOW}未运行😴${RESET}"
        return 0
    fi
    pid=$(cat "$pid_file")
    if [[ -z "$pid" ]] || ! sudo kill -0 "$pid" 2>/dev/null; then
        echo -e "${FG_YELLOW}未运行😴${RESET}"
        # sudo rm -f "$pid_file" 2>/dev/null # 可选清理
        return 0
    fi
    cmdline=$(ps -o cmd= -p "$pid" 2>/dev/null)
    if [[ "$cmdline" =~ .*-q[[:space:]]+([0-9]{4,}) ]]; then
        qq_account="${BASH_REMATCH[1]}"
        echo -e "${FG_GREEN}运行中😋 - ${BOLD}$qq_account${RESET}"
        return 0
    else
        # 尝试查找子进程 (更健壮的方式)
        local child_pids=$(pgrep -P "$pid")
        for child_pid in $child_pids; do
            child_cmdline=$(ps -o cmd= -p "$child_pid" 2>/dev/null)
            # 查找包含 qq 和 -q 参数的子进程命令行
            if [[ "$child_cmdline" =~ qq.*-q[[:space:]]+([0-9]{4,}) ]]; then
                 qq_account="${BASH_REMATCH[1]}"
                 echo -e "${FG_GREEN}运行中😋 - ${BOLD}$qq_account${RESET}"
                 return 0
            fi
        done
        # 如果主进程和子进程都没找到有效信息
        echo -e "${FG_RED}状态未知🤔 (PID: ${BOLD}$pid${RESET})${RESET}"
        return 0
    fi
}

# 函数：执行登录
start_napcat_login() {
    local qq_account=$1
    local pid_file="/var/run/napcat.pid"
    local log_file="/var/log/napcat_${qq_account}.log"
    local config_file="$CONFIG_DIR/onebot11_${qq_account}.json"
    local existing_pid=""

    # 1. 检查现有进程
    if [[ -f "$pid_file" ]] && [[ -r "$pid_file" ]]; then
        existing_pid=$(cat "$pid_file")
        if [[ -n "$existing_pid" ]] && sudo kill -0 "$existing_pid" 2>/dev/null; then
            # 进程存在，询问用户
            dialog --colors --title "进程冲突" --yesno "检测到 Napcat 进程 (PID: ${BOLD}$existing_pid${RESET}) 可能正在运行。\n\n是否终止现有进程并继续启动？" 10 65 2>&1 >/dev/tty # 加粗 PID，调整宽度
            local choice=$?
            clear
            if [[ $choice -eq 0 ]]; then # Yes - 终止进程
                echo -e "${ANSI_YELLOW}正在尝试终止现有进程 (PID: ${ANSI_BOLD}$existing_pid${ANSI_RESET})${ANSI_YELLOW}...${ANSI_RESET}" # 加粗 PID
                sudo kill "$existing_pid" 2>/dev/null
                sleep 2
                if sudo kill -0 "$existing_pid" 2>/dev/null; then
                    echo -e "${ANSI_RED}无法正常终止进程，尝试强制终止...${ANSI_RESET}"
                    sudo kill -9 "$existing_pid" 2>/dev/null
                    sleep 1
                    if sudo kill -0 "$existing_pid" 2>/dev/null; then
                         dialog --colors --msgbox "错误：无法终止现有 Napcat 进程 (PID: ${ANSI_BOLD}$existing_pid${ANSI_RESET})。请手动检查并终止。" 8 65 # 加粗 PID，调整宽度
                         return 1 # 无法继续
                    fi
                fi
                echo -e "${ANSI_GREEN}现有进程已终止。${ANSI_RESET}"
                sudo rm -f "$pid_file"
            else # No - 取消
                dialog --colors --msgbox "启动已取消。" 6 40
                return 1
            fi
        else
             if [[ -n "$existing_pid" ]]; then
                 echo -e "${ANSI_YELLOW}检测到无效的 PID 文件 (PID: ${ANSI_BOLD}$existing_pid${ANSI_RESET})${ANSI_YELLOW}，已清理。${ANSI_RESET}" # 添加并加粗 PID
             fi
             sudo rm -f "$pid_file" 2>/dev/null
        fi
    fi

    # 2. 检查网络服务配置
    local has_network_service=false
    if [[ -f "$config_file" ]] && [[ -r "$config_file" ]]; then
        # 使用 jq 检查 network 下的数组是否至少有一个非空
        local jq_check_result=$(jq '
            (.network // null) as $net |
            if $net == null then
                false
            else
                ( ($net.httpServers // []) | length > 0 ) or
                ( ($net.httpClients // []) | length > 0 ) or
                ( ($net.websocketServers // []) | length > 0 ) or
                ( ($net.websocketClients // []) | length > 0 )
            end
        ' "$config_file" 2>/dev/null)

        if [[ "$jq_check_result" == "true" ]]; then
            has_network_service=true
        fi
    fi

    if ! $has_network_service; then
        dialog --colors --title "网络服务未配置" --yesno "警告：账号 ${FG_CYAN}${BOLD}$qq_account${RESET} 未启用任何网络服务 (HTTP/WebSocket 服务端或客户端)。\n\n这可能导致机器人无法与外部应用交互。\n\n是否仍要继续启动 Napcat？" 12 70 2>&1 >/dev/tty # 加粗账号
        local choice=$?
        clear
        if [[ $choice -ne 0 ]]; then # No - 取消
            dialog --colors --msgbox "启动已取消。" 6 40
            return 1
        fi
    fi

    # 3. 启动 Napcat
    clear
    echo -e "${ANSI_GREEN}正在尝试为账号 ${ANSI_BOLD}$qq_account${ANSI_RESET}${ANSI_GREEN} 启动 Napcat...${ANSI_RESET}"
    echo "日志文件: $log_file"
    # 确保日志目录存在 (如果需要)
    # sudo mkdir -p /var/log
    # sudo touch "$log_file"
    # sudo chown $(whoami) "$log_file" # 确保当前用户可写，如果 sudo 保留了权限

    # 使用 sudo 启动 xvfb-run 和 qq，并将输出重定向到日志文件
    # 注意：确保 /var/log 目录和该日志文件对于执行 sudo 的用户或 qq 进程是可写的
    # 可能需要调整权限或使用 sudo sh -c '...' 结构
    sudo /usr/bin/xvfb-run -a qq --no-sandbox -q "$qq_account" > "$log_file" 2>&1 &
    NAPCAT_PID=$!

    # 检查后台命令是否成功启动 (PID 是否大于 0)
    if [[ "$NAPCAT_PID" -le 0 ]]; then
        dialog --colors --msgbox "错误：启动 Napcat 失败，未能获取进程 PID。" 8 60
        return 1
    fi

    echo "Napcat 进程 PID: $NAPCAT_PID"

    # 将 PID 写入文件 (使用 sudo tee 保证权限)
    echo "$NAPCAT_PID" | sudo tee "$pid_file" > /dev/null
    if [[ $? -ne 0 ]]; then
         dialog --colors --msgbox "${FG_YELLOW}警告：无法将 PID 写入 '${BOLD}$pid_file${RESET}${FG_YELLOW}'。请检查权限。${RESET}" 8 65 # 加粗文件名，调整宽度
         # 不一定需要退出，但记录一下
    fi
    echo -e "${ANSI_GREEN}Napcat 正在后台启动... 正在监控日志...${ANSI_RESET}"

    # 4. 监控日志文件
    local timeout=15 # 初始超时时间（秒）
    local qr_timeout=60 # 扫码后的登录超时时间
    local found_login=false
    local tailbox_pid=""

    # 等待日志文件生成
    local wait_log_count=5
    while [[ ! -f "$log_file" ]] && [[ $wait_log_count -gt 0 ]]; do
        sleep 1
        ((wait_log_count--))
    done

    if [[ ! -f "$log_file" ]]; then
        dialog --colors --msgbox "${FG_RED}错误：等待日志文件 '${BOLD}$log_file${RESET}${FG_RED}' 生成超时。${RESET}" 8 65 # 加粗文件名，调整宽度
        return 1
    fi

    while [[ $timeout -gt 0 ]]; do
        # 检查登录成功关键字
        if grep -q "配置加载" "$log_file"; then
            dialog --colors --title "登录成功" --infobox "Napcat (账号: ${BOLD}$qq_account${RESET}) 已成功登录！" 5 55 # 加粗账号，调整宽度
            sleep 2 # 显示信息一会儿
            found_login=true
            break
        fi

        # 检查二维码关键字
        if grep -q "二维码" "$log_file"; then
            clear # 清理屏幕，准备显示提示
            echo -e "${ANSI_YELLOW}检测到登录二维码，请在 Napcat 日志中查看并扫描：${ANSI_RESET}"
            echo -e "$$log_file" # 加粗日志文件名
            echo -e "${ANSI_YELLOW}注意：即将显示的是日志快照，二维码可能会刷新。${ANSI_RESET}"
            echo -e "${ANSI_YELLOW}如果扫描失败，请直接查看日志文件获取最新二维码。${ANSI_RESET}"
            echo -e "${ANSI_YELLOW}正在后台监控登录状态 (${ANSI_BOLD}${qr_timeout}${ANSI_RESET}${ANSI_YELLOW}秒)...${ANSI_RESET}" # 加粗超时时间
            sleep 1
            cat "$log_file"
            echo -e "${ANSI_YELLOW}正在后台监控登录状态 (${qr_timeout}秒)...${ANSI_RESET}"
            # tailbox_pid 不再需要
            tailbox_pid=""

            # 开始监控扫码后的登录
            echo -e "${ANSI_YELLOW}检测到二维码，请扫描。正在后台监控登录状态 (${qr_timeout}秒)...${ANSI_RESET}"
            local qr_wait=$qr_timeout
            while [[ $qr_wait -gt 0 ]]; do
                 if grep -q "配置加载" "$log_file"; then
                     # 关闭 tailbox
                     if [[ -n "$tailbox_pid" ]] && kill -0 "$tailbox_pid" 2>/dev/null; then
                         kill "$tailbox_pid" 2>/dev/null
                     fi
                     dialog --colors --title "登录成功" --infobox "Napcat (账号: $qq_account) 已成功登录！" 5 50
                     sleep 2
                     found_login=true
                     break 2 # 跳出内外两层循环
                 fi
                 sleep 1
                 ((qr_wait--))
            done

            # 如果是因为超时退出内层循环
            if ! $found_login; then
                 # 关闭 tailbox
                 if [[ -n "$tailbox_pid" ]] && kill -0 "$tailbox_pid" 2>/dev/null; then
                     kill "$tailbox_pid" 2>/dev/null
                 fi
                 dialog --colors --title "登录超时" --msgbox "${FG_YELLOW}扫描二维码后登录超时或失败。\n请检查日志: ${BOLD}$log_file${RESET}" 8 65 # 加粗文件名，调整宽度
                 # 这里不 return，让外层循环也结束
            fi
            break # 跳出外层循环 (无论内层是否成功)
        fi

        sleep 1
        ((timeout--))
    done

    # 清理可能残留的 tailbox 进程
    if [[ -n "$tailbox_pid" ]] && kill -0 "$tailbox_pid" 2>/dev/null; then
        kill "$tailbox_pid" 2>/dev/null
    fi

    # 如果最终没有登录成功
    if ! $found_login; then
        dialog --colors --title "状态未知" --msgbox "${FG_YELLOW}Napcat 状态异常或超时。\n未在日志中检测到明确的登录成功或二维码信息。\n请手动检查日志: ${BOLD}$log_file${RESET}" 10 70 # 加粗文件名
        return 1 # 返回错误状态
    fi

    return 0 # 成功完成（或至少启动并监控了一段时间）
}

# --- 主逻辑 ---

while true; do
    NAPCAT_STATUS=$(get_napcat_status)
    ACCOUNTS_LIST_STR=$(get_qq_accounts)
    # 检查 get_qq_accounts 是否返回错误信息
    if [[ "$ACCOUNTS_LIST_STR" == "ERROR:"* ]]; then
         dialog --colors --msgbox "错误：无法获取账号列表，请检查配置目录 '$CONFIG_DIR'。" 8 60
         exit 1
    fi
    ACCOUNTS_LIST=($ACCOUNTS_LIST_STR) # 将字符串转为数组

    MENU_ITEMS=()
    CONFIG_TAG="GOTO_CONFIG" # 定义一个清晰的 tag 用于配置选项

    if [[ ${#ACCOUNTS_LIST[@]} -eq 0 ]]; then
        # 没有找到账户，只显示配置选项
        MENU_ITEMS+=("$CONFIG_TAG" "${FG_YELLOW}没有任何已配置的QQ账户，请前往配置添加${RESET}")
    else
        # 找到了账户，列出账户作为启动选项
        # 使用 QQ 号本身作为 tag
        for acc in "${ACCOUNTS_LIST[@]}"; do
            MENU_ITEMS+=("$acc" "启动账号: ${FG_CYAN}$acc${RESET}")
        done
        # 添加配置选项
        MENU_ITEMS+=("$CONFIG_TAG" "配置 Napcat (账号/服务)")
    fi

    # 计算实际的菜单项数量 (账号数 + 添加项)
    num_entries=$(( ${#ACCOUNTS_LIST[@]} + 1 )) # 移除 local

    # 设置列表的期望显示高度 (例如，最多显示 8 行)
    list_height=$num_entries # 移除 local
    [[ $list_height -gt 8 ]] && list_height=8
    [[ $list_height -lt 1 ]] && list_height=1 # 确保至少为1

    # 计算对话框的总高度：列表高度 + 额外空间 (约 7 行)
    menu_height=$(( list_height + 7 )) # 移除 local
    [[ $menu_height -lt 10 ]] && menu_height=10 # 确保最小总高度

    CHOICE=$(dialog --colors --clear --backtitle "Napcat 启动器" \
                    --title "启动 Napcat" \
                    --ok-label "选择" \
                    --cancel-label "退出" \
                    --extra-button --extra-label "刷新状态" \
                    --menu "状态：${NAPCAT_STATUS}\n请选择操作:" \
                    "$menu_height" 70 "$list_height" \
                    "${MENU_ITEMS[@]}" \
                    2>&1 >/dev/tty)

    exit_status=$?
    clear

    case $exit_status in
        0) 
            case "$CHOICE" in
                "$CONFIG_TAG") 
                    # 检查 Config.sh 是否存在且可执行
                    if [[ -f "$CONFIG_SCRIPT" ]] && [[ -x "$CONFIG_SCRIPT" ]]; then
                        "$CONFIG_SCRIPT" # 执行配置脚本
                    else
                        dialog --colors --msgbox "错误：无法找到或执行配置脚本 '$CONFIG_SCRIPT'。" 8 60
                    fi
                    ;;
                *) # 假定用户选择了一个 QQ 账号
                    # 检查选择的是否是有效的账号 (从 ACCOUNTS_LIST 验证)
                    is_valid_account=false
                    for acc in "${ACCOUNTS_LIST[@]}"; do
                        if [[ "$CHOICE" == "$acc" ]]; then
                            is_valid_account=true
                            break
                        fi
                    done

                    if $is_valid_account; then
                        # 确认是有效账号后，调用启动函数
                        start_napcat_login "$CHOICE"
                    else
                        # 如果 CHOICE 不是配置 TAG 也不是列表中的有效账号
                        dialog --colors --msgbox "出现意外错误，无效的选择: '$CHOICE'" 6 40
                    fi
                    ;;
            esac
            ;;
        1) 
            echo "已退出 Napcat 启动器。"
            break # 退出主循环
            ;;
        3) 
            continue
            ;;
        *) 
            echo "操作已取消或发生未知错误 (退出码: $exit_status)。"
            break # 退出主循环
            ;;
    esac
done

# 清理屏幕
clear