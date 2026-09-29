#!/bin/bash
# 卸载 wg-quick 免密提权白名单（需 sudo 运行）:
#   sudo ./Scripts/uninstall.sh
set -euo pipefail

RULE_FILE="/etc/sudoers.d/wireguard-tray"
if [[ -f "$RULE_FILE" ]]; then
    rm -f "$RULE_FILE"
    echo "✅ 已删除 $RULE_FILE"
else
    echo "未找到 $RULE_FILE，无需卸载"
fi
