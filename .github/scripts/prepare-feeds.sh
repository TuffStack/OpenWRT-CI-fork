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
# 同时按 WRT_FEEDS 中 mode=official-feed 的条目注册官方 src-git（nikki），
# 使 ./scripts/feeds update/install 直接按上游推荐方式安装，而不是复制仓库。

set -euo pipefail

BASE_CFG="${GITHUB_WORKSPACE:-$PWD}/Config/BASE.txt"
[ -f "$BASE_CFG" ] || { echo "::error::缺少 $BASE_CFG"; exit 1; }

mapfile -t DISABLED < <(grep -oP '^CONFIG_FEED_\K[^=]+(?==n\s*$)' "$BASE_CFG" || true)
if [ "${#DISABLED[@]}" -eq 0 ]; then
	echo "feeds: BASE.txt 未禁用任何 feed"
fi

# 官方源注册：src-git 写进生效的 feeds.conf（feeds.conf 优先于 feeds.conf.default），
# 用标记行保证重复执行不叠加；清单未声明官方源时同时清掉旧标记，避免遗留 feed。
register_official_feeds() {
	local CONF="$1"
	python3 - "$CONF" <<'PY'
import json, os, sys
from pathlib import Path

conf = Path(sys.argv[1])
raw = os.environ.get("WRT_FEEDS", "").strip()
feeds = []
if raw:
    feeds = json.loads(raw)
else:
    # 本地单独调试：与 Packages.sh 保持一致，按 WRT_PROFILE 从清单取值
    workspace = Path(os.environ.get("GITHUB_WORKSPACE", os.getcwd()))
    cfg_path = workspace / "Config" / "builds.json"
    profile = os.environ.get("WRT_PROFILE", "")
    if profile and cfg_path.is_file():
        cfg = json.loads(cfg_path.read_text(encoding="utf-8"))
        keys = sorted(set(cfg["commonFeeds"]) | set(cfg["profiles"][profile].get("feeds", [])))
        feeds = [cfg["feeds"][k] for k in keys]

official = [f for f in feeds if f.get("mode") == "official-feed"]
names = {f["name"] for f in official}
lines = conf.read_text(encoding="utf-8").splitlines(keepends=True)
kept = []
for line in lines:
    if line.startswith("# official-feed: "):
        continue
    parts = line.split()
    if len(parts) >= 2 and parts[0] == "src-git" and parts[1] in names:
        continue
    kept.append(line)
for f in official:
    kept.append("# official-feed: %s\n" % f["name"])
    kept.append("src-git %s https://github.com/%s.git;%s\n" % (f["name"], f["repo"], f["branch"]))
conf.write_text("".join(kept), encoding="utf-8")
if official:
    print("feeds: %s 注册官方源 %s" % (conf, ", ".join(sorted(names))))
PY
}

FOUND_CONF=0
ACTIVE_CONF=""
for CONF in feeds.conf feeds.conf.default; do
	[ -f "$CONF" ] || continue
	FOUND_CONF=1
	[ -n "$ACTIVE_CONF" ] || ACTIVE_CONF="$CONF"
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
register_official_feeds "$ACTIVE_CONF"

# git clean -ffdx -e feeds 保留了 feeds/ 下的 clone；feeds install 创建的
# package/feeds/<name> 链接也要一起删，否则悬空链接仍会被扫描
for FEED in "${DISABLED[@]}"; do
	rm -rf "feeds/$FEED" "feeds/$FEED.index" "feeds/$FEED.tmp" "package/feeds/$FEED"
done
