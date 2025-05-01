#!/bin/bash

# 函数：检查 NapCatQQ 更新
# 返回值:
#  1: 检测到新版本 (API 版本 > 本地版本)
#  0: 当前已是最新版本 (API 版本 <= 本地版本)
# -1: 无法获取远程版本或无法读取/解析本地版本

# !!!!!!注意本文件只是API测试在实际脚本中仍然有同样的函数并没有使用导入!!!!!!!
check_for_update() {
    local urls=(
        "https://nclatest.znin.net/"
        "https://jiashu.1win.eu.org/https://api.github.com/repos/NapNeko/NapCatQQ/releases/latest"
		"https://napcatversion.109834.xyz/https://api.github.com/repos/NapNeko/NapCatQQ/releases/latest"
        "https://spring-night-57a1.3540746063.workers.dev/https://api.github.com/repos/NapNeko/NapCatQQ/releases/latest"
		"https://api.github.com/repos/NapNeko/NapCatQQ/releases/latest"
    )
    local result_file
    result_file=$(mktemp) # Make temp file local to function scope
    # Setup trap local to the function's execution context
    trap 'rm -f "$result_file"; pkill -P $$ &>/dev/null' RETURN INT TERM

    local latest_tag_numeric=""
    local original_tag=""
    local numeric_tag=""

    # --- 子函数：获取标签并写入临时文件 (保持不变) ---
    fetch_and_write() {
        local url="$1"
        local tmp_file="$2"
        local tag
        # 将 jq 的 stderr 重定向到 /dev/null
        tag=$(curl -s --connect-timeout 5 "$url" | jq -r '.tag_name // empty' 2>/dev/null)
        # 检查 jq 的退出状态以及 tag 是否有效
        if [[ $? -eq 0 ]] && [[ -n "$tag" ]] && [[ "$tag" != "null" ]]; then
            (
                # 使用 flock 确保只有一个进程写入文件
                flock -n 9 || exit 1
                # 再次检查文件是否为空，防止并发写入覆盖
                if [[ ! -s "$tmp_file" ]]; then
                    echo "$tag" > "$tmp_file"
                fi
            ) 9>"$tmp_file"
        # else # 可选：如果需要记录 jq 失败，可以在这里添加日志
            # echo "jq failed or returned empty/null for $url" >&2
        fi
    }
    # --- 子函数结束 ---

    # --- 并发获取远程版本 ---
    local url
    for url in "${urls[@]}"; do
        fetch_and_write "$url" "$result_file" &
    done

    local wait_timeout=5
    local i
    for (( i=0; i < wait_timeout * 10; i++ )); do
        if [[ -s "$result_file" ]]; then
            break
        fi
        sleep 0.1
    done
    # --- 获取结束 ---

    # --- 处理远程版本结果 ---
    if [[ -s "$result_file" ]]; then
        original_tag=$(head -n 1 "$result_file")
        # 去除 v 和 . 只留下数字
        numeric_tag="${original_tag//[v.]/}"
        echo "获取到最新发布版本的数字标签是: $numeric_tag"
        latest_tag_numeric=$numeric_tag
    else
        echo "错误：在 ${wait_timeout} 秒内未能从任何源获取远程版本标签。" >&2
        return -1 # API 查询失败
    fi
    # --- 处理结束 ---

    # --- 获取并处理本地版本 ---
    local local_file="/opt/QQ/resources/app/app_launcher/napcat/napcat.mjs"
    local local_version_string=""
    local local_version_numeric=""

    if [[ ! -f "$local_file" ]] || [[ ! -r "$local_file" ]]; then
        echo "错误：无法读取本地文件 '$local_file'。" >&2
        return -1 # 无法读取本地文件，视为失败
    fi

    # 尝试提取版本字符串
    # 使用 grep 查找包含 'const version = "' 的行，然后用 sed 提取引号内的内容
    local_version_string=$(grep 'const version = "' "$local_file" | sed -n 's/.*const version = "\([^"]*\)".*/\1/p')

    if [[ -z "$local_version_string" ]]; then
        echo "错误：无法在 '$local_file' 中找到 'const version = \"...\"' 格式的版本号。" >&2
        return -1 # 无法解析本地版本，视为失败
    fi

    # 去除 v 和 . 只留下数字
    local_version_numeric="${local_version_string//[v.]/}"
    echo "获取到本地版本的数字标签是: $local_version_numeric"
    # --- 本地版本处理结束 ---

    # --- 版本比较 ---
    # 确保两者都是数字（或至少看起来像数字）
    if ! [[ "$latest_tag_numeric" =~ ^[0-9]+$ ]] || ! [[ "$local_version_numeric" =~ ^[0-9]+$ ]]; then
         echo "错误：获取到的版本号格式不正确，无法比较。" >&2
         return -1 # 版本号格式错误
    fi

    # 使用 Bash 算术比较
    if [[ "$latest_tag_numeric" -gt "$local_version_numeric" ]]; then
        echo "检测到新版本 (远程: $original_tag > 本地: $local_version_string)。"
        return 1 # API 版本大于本地版本
    else
        echo "当前已是最新版本或更新 (远程: $original_tag <= 本地: $local_version_string)。"
        return 0 # API 版本小于或等于本地版本
    fi
    # --- 比较结束 ---
}

