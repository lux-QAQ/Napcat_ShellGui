#!/bin/bash
FILE="data.json"

# 列出顶层键
KEYS=($(jq -r 'keys_unsorted[]' "$FILE"))
# 构造 dialog 菜单项
MENU=()
for k in "${KEYS[@]}"; do
  MENU+=("$k" "")
done

# 菜单选择
CHOICE=$(dialog --clear --menu "选择要编辑的键" 15 50 5 "${MENU[@]}" 2>&1 >/dev/tty)
clear

# 获取当前值并输入新值
CUR=$(jq -r ".${CHOICE}" "$FILE")
NEW=$(dialog --clear --inputbox "当前 ${CHOICE}：" 8 40 "$CUR" 2>&1 >/dev/tty)
clear

# 更新并保存
jq --arg v "$NEW" ".${CHOICE} = \$v" "$FILE" > tmp.json && mv tmp.json "$FILE"
echo "已将 ${CHOICE} 更新为 ${NEW}"
