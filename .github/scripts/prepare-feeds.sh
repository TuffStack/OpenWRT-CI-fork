#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY
#
# .github/scripts/prepare-feeds.sh —— 按 Config/BASE.txt 移除不需要的 feed
# 执行目录：wrt/
#
# CONFIG_FEED_xxx=n 只是 Kconfig 符号开关，挡不住 ./scripts/feeds update -a 克隆并
# 扫描整个 feed。feeds/video 里 Qt5/Qt6 的 Kconfig 循环、qBittorrent 的缺失依赖等
# 噪声都来自这里。让 BASE.txt 同时作为"禁用哪些 feed"的唯一真源，在注册阶段就摘掉，
# 并清理上次构建的残留（Sync Code 的 git clean 用 -e feeds 保留了 feeds/）。

set -euo pipefail

BASE_CFG="${GITHUB_WORKSPACE:-$PWD}/Config/BASE.txt"
[ -f "$BASE_CFG" ] || { echo "::error::缺少 $BASE_CFG"; exit 1; }

mapfile -t DISABLED < <(grep -oP '^CONFIG_FEED_\K[^=]+(?==n\s*$)' "$BASE_CFG" || true)
if [ "${#DISABLED[@]}" -eq 0 ]; then
	echo "feeds: BASE.txt 未禁用任何 feed"
	exit 0
fi

FOUND_CONF=0
for CONF in feeds.conf feeds.conf.default; do
	[ -f "$CONF" ] || continue
	FOUND_CONF=1
	python3 - "$CONF" "${DISABLED[@]}" <<'PY'
import sys

conf, disabled = sys.argv[1], set(sys.argv[2:])
with open(conf, encoding="utf-8") as f:
    lines = f.readlines()

kept = []
for line in lines:
    parts = line.split()
    if len(parts) >= 2 and parts[0].startswith("src-") and parts[1] in disabled:
        continue
    kept.append(line)

with open(conf, "w", encoding="utf-8") as f:
    f.writelines(kept)
print(f"feeds: {conf} 移除 {len(lines) - len(kept)} 行 ({', '.join(sorted(disabled))})")
PY
done
[ "$FOUND_CONF" -eq 1 ] || { echo "::error::找不到 feeds.conf / feeds.conf.default"; exit 1; }

# git clean -ffdx -e feeds 保留了 feeds/ 下的 clone；feeds install 创建的
# package/feeds/<name> 链接也要一起删，否则悬空链接仍会被扫描
for FEED in "${DISABLED[@]}"; do
	rm -rf "feeds/$FEED" "feeds/$FEED.index" "feeds/$FEED.tmp" "package/feeds/$FEED"
done
