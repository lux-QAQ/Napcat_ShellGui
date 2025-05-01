#!/bin/bash

# 检查 dialog --colors 是否安装
if ! command -v dialog --colors &> /dev/null; then
    echo "错误: 需要 'dialog --colors' 命令，请先安装。" >&2
    echo "例如: sudo apt update && sudo apt install dialog --colors" >&2
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


# --- ANSI 颜色定义 (使用 ANSI-C Quoting) ---
RESET='\Zn'      # 重置为正常
BOLD='\Zb'       # 切换粗体 (效果取决于终端和 dialog --colors 版本)

# 前景色
FG_BLACK='\Z0'
FG_RED='\Z1'
FG_GREEN='\Z2'
FG_YELLOW='\Z3'
FG_BLUE='\Z4'
FG_MAGENTA='\Z5'
FG_CYAN='\Z6'
FG_WHITE='\Z7'

# --- 函数定义 ---



# 正向WS配置
configure_http_server() {
    local qq_account=$1
    local config_file="$CONFIG_DIR/onebot11_${qq_account}.json"
    local temp_file=$(mktemp) || { echo "无法创建临时文件"; exit 1; }
    trap 'rm -f "$temp_file"' EXIT # 确保退出时删除临时文件

    # 检查配置文件是否存在且可读
    if [[ ! -f "$config_file" ]] || [[ ! -r "$config_file" ]]; then
        dialog --colors --msgbox "错误：无法读取配置文件 '$config_file'。" 8 60
        return 1
    fi

    # --- 读取当前配置或设置默认值 ---
    local mode="create" # 默认为新建模式
    local current_name=""
    local current_host="0.0.0.0"
    local current_port="3000"
    local current_token=""
    local current_msg_format="array"
    local current_enable="off"
    local current_debug="off"
    local current_cors="on"
    local current_ws="on"

    # 尝试读取 network.httpServers[0]
    local server_config=$(jq -c '.network.httpServers[0] // null' "$config_file")

    if [[ "$server_config" != "null" ]]; then
        mode="modify"
        current_name=$(echo "$server_config" | jq -r '.name // ""')
        current_host=$(echo "$server_config" | jq -r '.host // "0.0.0.0"')
        current_port=$(echo "$server_config" | jq -r '.port // "3000"')
        current_token=$(echo "$server_config" | jq -r '.token // ""')
        current_msg_format=$(echo "$server_config" | jq -r '.messagePostFormat // "array"')
        [[ $(echo "$server_config" | jq -r '.enable // false') == "true" ]] && current_enable="on"
        [[ $(echo "$server_config" | jq -r '.debug // false') == "true" ]] && current_debug="on"
        [[ $(echo "$server_config" | jq -r '.enableCors // true') == "true" ]] && current_cors="on" # 默认开启
        [[ $(echo "$server_config" | jq -r '.enableWebsocket // true') == "true" ]] && current_ws="on" # 默认开启
    fi

    local title_prefix="${FG_GREEN}新建${RESET}"
    [[ "$mode" == "modify" ]] && title_prefix="${FG_YELLOW}修改${RESET}"

    while true; do
        # --- 显示表单 ---
        # 1. 输入框部分
        exec 3>&1
        local form_values=$(dialog --colors --clear --backtitle "HTTP 服务端配置" \
            --title "$title_prefix HTTP 服务端 - $qq_account" \
            --form "请填写以下信息 (带 * 为必填):" 18 70 0 \
            "名称 (*):"     1 1 "$current_name"     1 15 40 0 \
            "Host (*):"     2 1 "$current_host"     2 15 40 0 \
            "Port (*):"     3 1 "$current_port"     3 15 40 0 \
            "Token:"        4 1 "$current_token"    4 15 40 0 \
        2>&1 1>&3)
        local form_exit_status=$?
        exec 3>&-
        clear

        if [[ $form_exit_status -ne 0 ]]; then
            dialog --colors --msgbox "操作已取消。" 6 40
            return 1
        fi

        # 解析表单输入
        local name=$(echo "$form_values" | sed -n '1p')
        local host=$(echo "$form_values" | sed -n '2p')
        local port=$(echo "$form_values" | sed -n '3p')
        local token=$(echo "$form_values" | sed -n '4p')

        # 2. 消息格式选择
        exec 3>&1
        local msg_format_choice=$(dialog --colors --clear --backtitle "HTTP 服务端配置" \
            --title "选择消息格式 - $qq_account" \
            --radiolist "请选择上报消息格式:" 10 40 2 \
            "array"  "数组格式" $([[ "$current_msg_format" == "array" ]] && echo "on" || echo "off") \
            "string" "字符串格式" $([[ "$current_msg_format" == "string" ]] && echo "on" || echo "off") \
        2>&1 1>&3)
        local radio_exit_status=$?
        exec 3>&-
        clear

        if [[ $radio_exit_status -ne 0 ]]; then
            dialog --colors --msgbox "操作已取消。" 6 40
            return 1
        fi
        local msg_format="$msg_format_choice" # radiolist 直接返回选中的 tag

        # 3. 开关选择
        exec 3>&1
        local checklist_choices=$(dialog --colors --clear --backtitle "HTTP 服务端配置" \
            --title "启用选项 - $qq_account" \
            --checklist "请选择要启用的选项:" 15 50 4 \
            "enable"    "启用服务"      "$current_enable" \
            "debug"     "开启Debug"     "$current_debug" \
            "cors"      "启用CORS"      "$current_cors" \
            "websocket" "启用Websocket" "$current_ws" \
        2>&1 1>&3)
        local check_exit_status=$?
        exec 3>&-
        clear

        if [[ $check_exit_status -ne 0 ]]; then
            dialog --colors --msgbox "操作已取消。" 6 40
            return 1
        fi

        # 解析 checklist 输出
        local enable=false; [[ "$checklist_choices" == *enable* ]] && enable=true
        local debug=false;  [[ "$checklist_choices" == *debug* ]] && debug=true
        local cors=false;   [[ "$checklist_choices" == *cors* ]] && cors=true
        local ws=false;     [[ "$checklist_choices" == *websocket* ]] && ws=true

        # --- 输入验证 ---
        local errors=()

        # 必填项检查
        [[ -z "$name" ]] && errors+=("名称不能为空")
        [[ -z "$host" ]] && errors+=("Host不能为空")
        [[ -z "$port" ]] && errors+=("Port不能为空")

        # Host 格式检查
        if [[ -n "$host" ]]; then
            if [[ "$host" == "localhost" ]]; then
                host="0.0.0.0" # 替换 localhost
            elif ! [[ "$host" =~ ^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$ ]]; then
                 errors+=("Host '$host' 不是有效的 IPv4 地址格式")
            fi
        fi

        # Port 格式和范围检查 (简单检查是否为数字)
        if [[ -n "$port" ]] && ! [[ "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
            errors+=("Port '$port' 必须是 1-65535 之间的数字")
        fi

        # 名称唯一性检查 (仅在名称非空时进行)
        if [[ -n "$name" ]]; then
            local original_name_to_exclude=""
            [[ "$mode" == "modify" ]] && original_name_to_exclude=$(jq -r '.network.httpServers[0].name // ""' "$config_file")

            # 获取所有其他服务的名称
            local all_other_names=()
            readarray -t all_other_names < <(jq -r --arg exclude "$original_name_to_exclude" --arg current "$name" '
                .network | [
                    (.httpServers[]? | select(.name != $exclude and .name != $current) | .name), # 排除自己(修改模式)和当前输入
                    .httpClients[]?.name,
                    .websocketServers[]?.name,
                    .websocketClients[]?.name
                ] | map(select(. != null)) | .[]
            ' "$config_file")

            for other_name in "${all_other_names[@]}"; do
                if [[ "$name" == "$other_name" ]]; then
                    errors+=("名称 '$name' 与其他服务冲突")
                    break
                fi
            done
        fi


        # 端口占用检查 (仅在 Port 有效时进行)
        if [[ "$port" =~ ^[0-9]+$ ]] && [[ "$port" -ge 1 ]] && [[ "$port" -le 65535 ]]; then
            # 检查 TCP 监听端口
            if ss -tuln | grep -q ":${port}\s"; then
                 errors+=("端口 $port 可能已被占用")
            fi
        fi


        # --- 处理验证结果 ---
        if [[ ${#errors[@]} -gt 0 ]]; then
            # 错误标题用红色，错误项用黄色
            local error_msg="${FG_RED}输入无效:${RESET}\n\n"
            for error in "${errors[@]}"; do
                error_msg+=" - ${FG_YELLOW}$error${RESET}\n"
            done
            dialog --colors --msgbox "$error_msg" 15 60
            # 保留用户输入以便下次显示
            current_name="$name"
            current_host="$host"
            current_port="$port"
            current_token="$token"
            current_msg_format="$msg_format"
            [[ "$enable" == true ]] && current_enable="on" || current_enable="off"
            [[ "$debug" == true ]] && current_debug="on" || current_debug="off"
            [[ "$cors" == true ]] && current_cors="on" || current_cors="off"
            [[ "$ws" == true ]] && current_ws="on" || current_ws="off"
            continue # 返回循环，重新显示表单
        fi

        # --- 验证通过，构建 JSON 对象 ---
        local new_server_obj=$(jq -n \
            --arg name "$name" \
            --arg host "$host" \
            --argjson port "$port" \
            --arg token "$token" \
            --arg msg_format "$msg_format" \
            --argjson enable "$enable" \
            --argjson debug "$debug" \
            --argjson cors "$cors" \
            --argjson ws "$ws" \
            '{
                enable: $enable,
                name: $name,
                host: $host,
                port: $port,
                enableCors: $cors,
                enableWebsocket: $ws,
                messagePostFormat: $msg_format,
                token: $token,
                debug: $debug
            }')

        # --- 更新 JSON 文件 ---
        local jq_script=""
        local jq_stderr_file=$(mktemp) # 创建一个临时文件来捕获 jq 的 stderr
        # 确保 jq_stderr_file 也在退出时被删除
        trap 'rm -f "$temp_file" "$jq_stderr_file"' EXIT

        if [[ "$mode" == "modify" ]]; then
            # 修改模式：替换 httpServers 数组的第一个元素
            # 移除 | fromjson
            jq_script='.network.httpServers[0] = $new_obj'
        else
            # 新建模式：确保 network 和 httpServers 存在，然后添加
            # 移除 | fromjson
            jq_script='
                (.network //= {}) |
                (.network.httpServers //= []) |
                .network.httpServers += [$new_obj]
            '
            # 或者更健壮的写法，确保 network 是对象，httpServers 是数组
            # jq_script='
            #     (if .network == null or (.network|type) != "object" then .network = {} else . end) |
            #     (if .network.httpServers == null or (.network.httpServers|type) != "array" then .network.httpServers = [] else . end) |
            #     .network.httpServers += [$new_obj]
            # '
        fi

        # 执行 jq，将 stdout 重定向到 temp_file, 将 stderr 重定向到 jq_stderr_file
        if jq --argjson new_obj "$new_server_obj" "$jq_script" "$config_file" > "$temp_file" 2> "$jq_stderr_file"; then
            # 检查写入临时文件是否成功且内容不为空
            if [[ -s "$temp_file" ]]; then
                 # 备份原始文件 (可选但推荐)
                 # cp "$config_file" "$config_file.bak"
                 # 用临时文件覆盖原始文件
                 if mv "$temp_file" "$config_file"; then
                     dialog --colors --msgbox "${FG_GREEN}HTTP 服务端配置已成功 $title_prefix！${RESET}" 8 50
                     rm -f "$jq_stderr_file"
                     trap - EXIT
                     return 0
                 else
                     dialog --colors --msgbox "${FG_RED}错误：${RESET}无法更新配置文件 '$config_file'。权限问题？" 8 60
                     rm -f "$jq_stderr_file"
                     return 1
                 fi
            else
                 local jq_error=$(<"$jq_stderr_file")
                 # 错误消息用红色
                 dialog --colors --msgbox "${FG_RED}错误：${RESET}jq 处理后生成了空文件。请检查 jq 脚本和输入。\n\nJQ 输出(可能为空):\n$(cat "$temp_file")\n\n${FG_RED}JQ 错误:${RESET}\n$jq_error" 15 70
                 rm -f "$jq_stderr_file"
                 return 1
            fi
        else
            local jq_error=$(<"$jq_stderr_file")
            rm -f "$jq_stderr_file"
            # 错误消息用红色
            dialog --colors --msgbox "${FG_RED}错误：${RESET}使用 jq 更新 JSON 时出错。\n\n${FG_RED}JQ 错误:${RESET}\n$jq_error\n\n请检查 JSON 文件格式或 jq 命令。" 15 70
            return 1
        fi

        # 如果代码能执行到这里，说明更新逻辑有问题，强制退出循环避免死循环
        break
    done
}


# 反向HTTP客户端配置
configure_reverse_http_client() {
    local qq_account=$1
    local config_file="$CONFIG_DIR/onebot11_${qq_account}.json"
    local temp_file=$(mktemp) || { echo "无法创建临时文件"; exit 1; }
    local jq_stderr_file=$(mktemp) # 用于捕获 jq 错误
    # 确保临时文件和错误文件在退出时被删除
    trap 'rm -f "$temp_file" "$jq_stderr_file"' EXIT

    # 检查配置文件是否存在且可读
    if [[ ! -f "$config_file" ]] || [[ ! -r "$config_file" ]]; then
        dialog --colors --msgbox "${FG_RED}错误：${RESET}无法读取配置文件 '$config_file'。" 8 60
        return 1
    fi

    # --- 读取当前配置或设置默认值 ---
    local mode="create" # 默认为新建模式
    local current_name=""
    local current_url="http://localhost:8080" # 默认 URL
    local current_token=""
    local current_msg_format="array" # 默认消息格式
    local current_enable="off"       # 默认不启用
    local current_debug="off"        # 默认不开启 Debug
    local current_report_self="off" # 默认不上报自身消息

    # 尝试读取 network.httpClients[0]
    local client_config=$(jq -c '.network.httpClients[0] // null' "$config_file")

    if [[ "$client_config" != "null" ]]; then
        mode="modify"
        current_name=$(echo "$client_config" | jq -r '.name // ""')
        current_url=$(echo "$client_config" | jq -r '.url // "http://localhost:8080"')
        current_token=$(echo "$client_config" | jq -r '.token // ""')
        current_msg_format=$(echo "$client_config" | jq -r '.messagePostFormat // "array"')
        [[ $(echo "$client_config" | jq -r '.enable // false') == "true" ]] && current_enable="on"
        [[ $(echo "$client_config" | jq -r '.debug // false') == "true" ]] && current_debug="on"
        [[ $(echo "$client_config" | jq -r '.reportSelfMessage // false') == "true" ]] && current_report_self="on"
    fi

    local title_prefix="${FG_GREEN}新建${RESET}"
    [[ "$mode" == "modify" ]] && title_prefix="${FG_YELLOW}修改${RESET}"

    while true; do
        # --- 显示表单 ---
        # 1. 输入框部分
        exec 3>&1
        local form_values=$(dialog --colors --clear --backtitle "HTTP 客户端配置" \
            --title "$title_prefix HTTP 客户端 - $qq_account" \
            --form "请填写以下信息 (带 * 为必填):" 18 70 0 \
            "名称 (*):"     1 1 "$current_name"        1 15 40 0 \
            "Url (*):"      2 1 "$current_url"         2 15 60 0 \
            "Token:"        3 1 "$current_token"       3 15 40 0 \
        2>&1 1>&3)
        local form_exit_status=$?
        exec 3>&-
        clear

        if [[ $form_exit_status -ne 0 ]]; then
            dialog --colors --msgbox "操作已取消。" 6 40
            return 1
        fi

        # 解析表单输入
        local name=$(echo "$form_values" | sed -n '1p')
        local url=$(echo "$form_values" | sed -n '2p')
        local token=$(echo "$form_values" | sed -n '3p')

        # 2. 消息格式选择
        exec 3>&1
        local msg_format_choice=$(dialog --colors --clear --backtitle "HTTP 客户端配置" \
            --title "选择消息格式 - $qq_account" \
            --radiolist "请选择上报消息格式:" 10 40 2 \
            "array"  "数组格式" $([[ "$current_msg_format" == "array" ]] && echo "on" || echo "off") \
            "string" "字符串格式" $([[ "$current_msg_format" == "string" ]] && echo "on" || echo "off") \
        2>&1 1>&3)
        local radio_exit_status=$?
        exec 3>&-
        clear

        if [[ $radio_exit_status -ne 0 ]]; then
            dialog --colors --msgbox "操作已取消。" 6 40
            return 1
        fi
        local msg_format="$msg_format_choice"

        # 3. 开关选择
        exec 3>&1
        local checklist_choices=$(dialog --colors --clear --backtitle "HTTP 客户端配置" \
            --title "启用选项 - $qq_account" \
            --checklist "请选择要启用的选项:" 15 50 3 \
            "enable"      "启用服务"        "$current_enable" \
            "debug"       "开启Debug"       "$current_debug" \
            "report_self" "上报自身消息"    "$current_report_self" \
        2>&1 1>&3)
        local check_exit_status=$?
        exec 3>&-
        clear

        if [[ $check_exit_status -ne 0 ]]; then
            dialog --colors --msgbox "操作已取消。" 6 40
            return 1
        fi

        # 解析 checklist 输出
        local enable=false; [[ "$checklist_choices" == *enable* ]] && enable=true
        local debug=false;  [[ "$checklist_choices" == *debug* ]] && debug=true
        local report_self=false; [[ "$checklist_choices" == *report_self* ]] && report_self=true

        # --- 输入验证 ---
        local errors=()
        # URL 验证正则表达式 (Perl 兼容)
        local url_regex='\b(([\w-]+://?|www[.])[^\s()<>]+(?:\([\w\d]+\)|([^[:punct:]\s]|/)))'

        # 必填项检查
        [[ -z "$name" ]] && errors+=("名称不能为空")
        [[ -z "$url" ]] && errors+=("Url不能为空")

        # Url 格式检查
        # 使用 grep -P 进行 Perl 兼容正则表达式匹配
        if [[ -n "$url" ]] && ! echo "$url" | grep -Pq "$url_regex"; then
             errors+=("Url '$url' 格式不正确")
        fi

        # 名称唯一性检查 (仅在名称非空时进行)
        if [[ -n "$name" ]]; then
            local original_name_to_exclude=""
            # 在修改模式下，获取当前正在修改的客户端的原始名称
            [[ "$mode" == "modify" ]] && original_name_to_exclude=$(jq -r '.network.httpClients[0].name // ""' "$config_file")

            # 获取所有其他服务的名称 (排除当前修改项的原始名称和当前输入名称)
            local all_other_names=()
            # 使用 readarray 读取 jq 输出的多行结果
            readarray -t all_other_names < <(jq -r --arg exclude "$original_name_to_exclude" --arg current "$name" '
                .network | [
                    .httpServers[]?.name,
                    # 排除自己(修改模式下原始名称)和当前输入名称
                    (.httpClients[]? | select(.name != $exclude and .name != $current) | .name),
                    .websocketServers[]?.name,
                    .websocketClients[]?.name
                ] | map(select(. != null)) | .[]
            ' "$config_file")

            # 检查冲突
            for other_name in "${all_other_names[@]}"; do
                if [[ "$name" == "$other_name" ]]; then
                    errors+=("名称 '$name' 与其他服务冲突")
                    break # 找到一个冲突就够了
                fi
            done
        fi

        # --- 处理验证结果 ---
        if [[ ${#errors[@]} -gt 0 ]]; then
            # 错误标题用红色，错误项用黄色
            local error_msg="${FG_RED}输入无效:${RESET}\n\n"
            for error in "${errors[@]}"; do
                error_msg+=" - ${FG_YELLOW}$error${RESET}\n"
            done
            dialog --colors --msgbox "$error_msg" 15 70 # 增加宽度以显示 URL
            # 保留用户输入以便下次显示 (重要的交互改进)
            current_name="$name"
            current_url="$url"
            current_token="$token"
            current_msg_format="$msg_format"
            [[ "$enable" == true ]] && current_enable="on" || current_enable="off"
            [[ "$debug" == true ]] && current_debug="on" || current_debug="off"
            [[ "$report_self" == true ]] && current_report_self="on" || current_report_self="off"
            continue # 返回循环，重新显示表单
        fi

        # --- 验证通过，构建 JSON 对象 ---
        local new_client_obj=$(jq -n \
            --arg name "$name" \
            --arg url "$url" \
            --arg token "$token" \
            --arg msg_format "$msg_format" \
            --argjson enable "$enable" \
            --argjson debug "$debug" \
            --argjson report_self "$report_self" \
            '{
                enable: $enable,
                name: $name,
                url: $url,
                reportSelfMessage: $report_self,
                messagePostFormat: $msg_format,
                token: $token,
                debug: $debug
            }')

        # --- 更新 JSON 文件 ---
        local jq_script=""

        if [[ "$mode" == "modify" ]]; then
            # 修改模式：替换 httpClients 数组的第一个元素
            jq_script='.network.httpClients[0] = $new_obj'
        else
            # 新建模式：确保 network 和 httpClients 存在，然后添加
            jq_script='
                (.network //= {}) |
                (.network.httpClients //= []) |
                .network.httpClients += [$new_obj]
            '
        fi

        # 执行 jq，将 stdout 重定向到 temp_file, 将 stderr 重定向到 jq_stderr_file
        if jq --argjson new_obj "$new_client_obj" "$jq_script" "$config_file" > "$temp_file" 2> "$jq_stderr_file"; then
            # 检查写入临时文件是否成功且内容不为空
            if [[ -s "$temp_file" ]]; then
                 # 备份原始文件 (可选但推荐)
                 # cp "$config_file" "$config_file.bak"
                 # 用临时文件覆盖原始文件
                 if mv "$temp_file" "$config_file"; then
                     dialog --colors --msgbox "${FG_GREEN}HTTP 客户端配置已成功 $title_prefix！${RESET}" 8 50
                     # 成功后不再需要 trap，清理错误文件
                     rm -f "$jq_stderr_file"
                     trap - EXIT
                     return 0 # 成功退出函数
                 else
                     dialog --colors --msgbox "${FG_RED}错误：${RESET}无法更新配置文件 '$config_file'。权限问题？" 8 60
                     # 出错也清理错误文件
                     rm -f "$jq_stderr_file"
                     return 1 # 失败退出函数
                 fi
            else
                 # jq 成功执行但输出了空文件，这通常是 jq 脚本逻辑问题
                 local jq_error_output=$(<"$jq_stderr_file") # 读取 jq 的 stderr
                 dialog --colors --msgbox "${FG_RED}错误：${RESET}jq 处理后生成了空文件。请检查 jq 脚本和输入。\n\nJQ 输出(空):\n\n${FG_RED}JQ 错误:${RESET}\n$jq_error_output" 15 70
                 rm -f "$jq_stderr_file"
                 return 1 # 失败退出函数
            fi
        else
            # jq 命令执行失败
            local jq_error_output=$(<"$jq_stderr_file") # 读取 jq 的 stderr
            rm -f "$jq_stderr_file"
            dialog --colors --msgbox "${FG_RED}错误：${RESET}使用 jq 更新 JSON 时出错。\n\n${FG_RED}JQ 错误:${RESET}\n$jq_error_output\n\n请检查 JSON 文件格式或 jq 命令。" 15 70
            return 1 # 失败退出函数
        fi

        # 理论上不应执行到这里，因为上面有 return，但为保险起见加上 break
        break
    done
}


# 函数：获取有效的QQ账号列表
get_qq_accounts() {
    local accounts=()
    # 确保目录存在
    if [[ ! -d "$CONFIG_DIR" ]]; then
        dialog --colors --msgbox "错误：配置目录 '$CONFIG_DIR' 不存在。" 8 50
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
        NEW_QQ=$(dialog --colors --clear --backtitle "添加账号" \
                        --title "输入新QQ账号" \
                        --inputbox "请输入新增的QQ账号（至少4位数字）:" 10 40 \
                        2>&1 >/dev/tty)
        local exit_status=$?
        clear

        # 用户按了取消或ESC
        if [[ $exit_status -ne 0 ]]; then
            dialog --colors --msgbox "添加操作已取消。" 6 40
            return 1 # 表示取消
        fi

        # 验证输入是否为至少4位数字
        if [[ "$NEW_QQ" =~ ^[0-9]{4,}$ ]]; then
            local new_napcat_file="$CONFIG_DIR/napcat_${NEW_QQ}.json"
            local new_onebot_file="$CONFIG_DIR/onebot11_${NEW_QQ}.json"

            # 检查配置文件是否已存在
            if [[ -f "$new_napcat_file" || -f "$new_onebot_file" ]]; then
                 dialog --colors --yesno "账号 $NEW_QQ 的配置文件已存在，是否覆盖？" 8 50 2>&1 >/dev/tty
                 if [[ $? -ne 0 ]]; then # 用户选择 "否"
                     continue # 重新提示输入
                 fi
            fi

            # 检查基础配置文件是否存在
            if [[ ! -f "$BASE_NAPCAT_CONFIG" ]]; then
                dialog --colors --msgbox "错误：基础配置文件 '$BASE_NAPCAT_CONFIG' 不存在。" 8 60
                return 2 # 表示基础文件缺失
            fi
             if [[ ! -f "$BASE_ONEBOT_CONFIG" ]]; then
                dialog --colors --msgbox "错误：基础配置文件 '$BASE_ONEBOT_CONFIG' 不存在。" 8 60
                return 2 # 表示基础文件缺失
            fi

            # 复制文件
            cp "$BASE_NAPCAT_CONFIG" "$new_napcat_file" && \
            cp "$BASE_ONEBOT_CONFIG" "$new_onebot_file"

            if [[ $? -eq 0 ]]; then
                dialog --colors --msgbox "账号 $NEW_QQ 添加成功！\nNapcat 配置: $new_napcat_file\nOneBot 配置: $new_onebot_file" 10 70
                return 0 # 表示成功
            else
                dialog --colors --msgbox "错误：复制文件时出错，请检查权限或磁盘空间。" 8 60
                return 3 # 表示复制失败
            fi
        else
            dialog --colors --msgbox "输入无效！请输入至少4位数字。" 6 40
            # 循环继续，要求重新输入
        fi
    done
}

# 函数：显示网络服务配置菜单 (菜单2)
show_service_menu() {
    local qq_account=$1
    while true; do
        SERVICE_CHOICE=$(dialog --colors --clear --backtitle "网络服务配置" \
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
                configure_http_server "$qq_account" # 调用新函数
                ;;
            2)
                dialog --colors --msgbox "将为账号 $qq_account 配置 HTTP 客户端 (反向http) - 功能待实现" 8 60
                # configure_reverse_http_client "$qq_account"
                ;;
            3)
                dialog --colors --msgbox "将为账号 $qq_account 配置 WebSocket 服务端 (正向ws) - 功能待实现" 8 60
                # configure_ws_server "$qq_account"
                ;;
            4)
                dialog --colors --msgbox "将为账号 $qq_account 配置 WebSocket 客户端 (反向ws) - 功能待实现" 8 60
                # configure_reverse_ws_client "$qq_account"
                ;;
            *)
                dialog --colors --msgbox "无效的选择: $SERVICE_CHOICE" 6 40
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
        dialog --colors --msgbox "错误：无法获取账号列表，请检查配置目录 '$CONFIG_DIR'。" 8 60
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


    CHOICE=$(dialog --colors --clear --backtitle "QQ账号管理" \
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
                 # 这通常不应该发生，因为dialog --colors只返回菜单中的有效项
                 dialog --colors --msgbox "出现意外错误，无效的选择: $CHOICE" 6 40
            fi
            ;;
    esac
done

# 清理屏幕并退出