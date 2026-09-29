#!/bin/bash
# 安装 wg-quick 免密提权白名单（需 sudo 运行）:
#   sudo ./Scripts/install-sudoers.sh
#
# 安全说明：
# - 只放行 `wg-quick up <名称>` 与 `wg-quick down <名称>` 两个动作
# - 命令使用绝对路径，防止 PATH 劫持
# - 写入后立即校验 visudo -c；失败则回滚删除
set -euo pipefail

WG_QUICK="$(command -v wg-quick || true)"
if [[ -z "$WG_QUICK" ]]; then
    PREFIX="$(brew --prefix 2>/dev/null || echo /opt/homebrew)"
    for cand in "$PREFIX/bin/wg-quick" "$PREFIX/sbin/wg-quick" "$PREFIX/opt/wireguard-tools/sbin/wg-quick"; do
        if [[ -x "$cand" ]]; then WG_QUICK="$cand"; break; fi
    done
fi
if [[ -z "$WG_QUICK" ]]; then
    echo "错误: 未找到 wg-quick，请先: brew install wireguard-tools" >&2
    exit 1
fi
# 解析符号链接为真实路径（brew 的 bin 下通常是 symlink）
WG_QUICK="$(python3 -c "import os,sys; print(os.path.realpath('$WG_QUICK'))" 2>/dev/null || echo "$WG_QUICK")"
echo "wg-quick 路径: $WG_QUICK"

RULE_FILE="/etc/sudoers.d/wireguard-tray"
RULE="%admin ALL=(root) NOPASSWD: $WG_QUICK up *, $WG_QUICK down *"

echo "写入: $RULE_FILE"
echo "$RULE" > "$RULE_FILE"
chmod 440 "$RULE_FILE"

echo "校验: visudo -c"
if visudo -c 2>&1 | grep -q "$RULE_FILE parsed OK"; then
    echo "✅ 免密提权已生效（NOPASSWD 白名单）"
else
    echo "⚠️  visudo 校验输出异常，回滚规则文件" >&2
    rm -f "$RULE_FILE"
    exit 1
fi
