#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY
#
# Scripts/Packages.sh —— 按需准备包源
# 执行目录：wrt/
#
# 包源来自 WRT_FEEDS（JSON 数组，来自 Config/builds.json，由 plan 作业展开）。
# 是否安装由 Config/ENABLE.conf + WRT_PACKAGES 决定，这里只保证"包存在"。

PKG_CACHE="${WRT_PKG_CACHE:-/mnt/wrt/pkgcache}"
PKG_SRC_DIR=""   # 由 clone_or_update 写入，避免用 $(...) 捕获从而混入诊断输出

# 共用克隆逻辑：失败硬中止（exit 1 使构建步骤失败，避免插件静默缺失）
do_clone() {   # $1=REPO $2=BRANCH $3=DEST
	mkdir -p "$(dirname "$3")"
	rm -rf "$3"
	git clone --depth=1 --single-branch --branch "$2" "https://github.com/$1.git" "$3" \
		|| { echo "::error::clone failed: $1"; exit 1; }
}

# 持久化克隆：有则 fetch+reset+clean，无则 clone；结果路径写入全局变量 PKG_SRC_DIR
clone_or_update() {
	local REPO="$1" BRANCH="$2"
	local CACHE_DIR="$PKG_CACHE/${REPO//\//__}"
	PKG_SRC_DIR="$CACHE_DIR"
	if [ -d "$CACHE_DIR/.git" ]; then
		echo "Update cache: $REPO"
		# fetch/reset/clean 任一失败：退回全量重克隆，避免旧缓存被复制进固件
		if git -C "$CACHE_DIR" fetch --depth=1 origin "$BRANCH" \
			&& git -C "$CACHE_DIR" reset --hard FETCH_HEAD \
			&& git -C "$CACHE_DIR" clean -fdx; then
			:
		else
			echo "cache update failed for $REPO, re-cloning"
			do_clone "$REPO" "$BRANCH" "$CACHE_DIR"
		fi
	else
		echo "Clone cache: $REPO"
		do_clone "$REPO" "$BRANCH" "$CACHE_DIR"
	fi
}

UPDATE_PACKAGE() {
	local PKG_NAME=$1
	local PKG_REPO=$2
	local PKG_BRANCH=$3
	local PKG_SPECIAL=$4
	local PKG_LIST=("$PKG_NAME" $5)
	local REPO_NAME=${PKG_REPO#*/}

	echo " "

	# 删除本地可能存在的不同名称的软件包
	for NAME in "${PKG_LIST[@]}"; do
		echo "Search directory: $NAME"
		local FOUND_DIRS=$(find ./feeds -maxdepth 4 -type d -iname "*$NAME*" 2>/dev/null)

		if [ -n "$FOUND_DIRS" ]; then
			while read -r DIR; do
				rm -rf "$DIR"
				echo "Delete directory: $DIR"
			done <<< "$FOUND_DIRS"
		else
			echo "Not fonud directory: $NAME"
		fi
	done

	# 从持久缓存取源码（有则更新，无则克隆），再本地复制进 package 目录
	clone_or_update "$PKG_REPO" "$PKG_BRANCH"
	local SRC_DIR="$PKG_SRC_DIR"

	if [[ "$PKG_SPECIAL" == "pkg" ]]; then
		find "$SRC_DIR"/*/ -maxdepth 3 -type d -iname "*$PKG_NAME*" -prune -exec cp -rf {} ./package \;
	elif [[ "$PKG_SPECIAL" == "name" ]]; then
		cp -rf "$SRC_DIR" "./package/$PKG_NAME"
	else
		cp -rf "$SRC_DIR" "./package/$REPO_NAME"
	fi
}

# dpd-fw 根目录按层组织（bpf/ plugins/ userspace/ openwrt/），不是 flat feed，
# 直接 clone 到 package/ 或 src-git 都扫不到包。按官方 openwrt/feed/README.md 的
# Option B，把每个含 Makefile 的源目录以 PKG_NAME 链接进 package/dpd-fw/。
setup_dpd_feed() {
	local REPO="$1" BRANCH="$2"
	clone_or_update "$REPO" "$BRANCH"
	local SRC="$PKG_SRC_DIR"
	local DEST="./package/dpd-fw"
	local -A DPD_MAP=(
		[dpd-fastpath]="bpf/core"
		[dpd-napi]="userspace/dpd-napi"
		[router-acl]="plugins/dpd-acl"
		[einat-ebpf]="plugins/dpd-einat"
		[dpd-einat-sync]="plugins/dpd-einat-sync"
		[dpd-honk]="plugins/dpd-honk"
		[dpd-observe]="plugins/dpd-observe"
		[router-qos]="plugins/dpd-qos"
		[router-tuning]="plugins/dpd-tuning"
		[dpd-acl]="openwrt/meta/dpd-acl"
		[dpd-mwan]="openwrt/meta/dpd-mwan"
		[dpd-qos]="openwrt/meta/dpd-qos"
		[luci-app-dpd]="openwrt/luci-app-dpd"
	)

	rm -rf "$DEST"
	mkdir -p "$DEST"
	local NAME COUNT=0
	for NAME in "${!DPD_MAP[@]}"; do
		if [ -f "$SRC/${DPD_MAP[$NAME]}/Makefile" ]; then
			ln -sfn "$SRC/${DPD_MAP[$NAME]}" "$DEST/$NAME"
			COUNT=$((COUNT + 1))
		fi
	done
	echo "dpd-fw: linked $COUNT packages into $DEST"
	[ "$COUNT" -gt 0 ] || { echo "::error::dpd-fw 包目录结构变化，未找到任何 Makefile"; exit 1; }
}

# 正常由 plan 作业注入；本地单独调试时回退到清单按 profile 取值
if [ -z "${WRT_FEEDS:-}" ]; then
	BUILDS="${GITHUB_WORKSPACE:-$PWD}/Config/builds.json"
	[ -f "$BUILDS" ] || { echo "::error::缺少 WRT_FEEDS，且找不到 $BUILDS"; exit 1; }
	WRT_FEEDS=$(python3 -c '
import json, sys
cfg = json.load(open(sys.argv[1], encoding="utf-8"))
p = cfg["profiles"][sys.argv[2]]
keys = sorted(set(cfg["commonFeeds"]) | set(p.get("feeds", [])))
print(json.dumps([cfg["feeds"][k] for k in keys]))
' "$BUILDS" "${WRT_PROFILE:-}")
fi
python3 -c 'import json,sys; sys.exit(0 if isinstance(json.loads(sys.argv[1]),list) else 1)' "$WRT_FEEDS" \
	|| { echo "::error::WRT_FEEDS 不是 JSON 数组: $WRT_FEEDS"; exit 1; }

# 展开成 TSV，避免为每个字段起一个解析进程
while IFS=$'\t' read -r F_NAME F_REPO F_BRANCH F_SPECIAL F_PRUNE F_MODE; do
	[ -n "$F_NAME" ] || continue
	case "$F_MODE" in
		package)   UPDATE_PACKAGE "$F_NAME" "$F_REPO" "$F_BRANCH" "$F_SPECIAL" "$F_PRUNE" ;;
		dpd-index) setup_dpd_feed "$F_REPO" "$F_BRANCH" ;;
		*)         echo "::warning::未知包源模式 $F_MODE（$F_NAME），跳过" ;;
	esac
done < <(python3 -c '
import json, sys
for f in json.loads(sys.argv[1]):
    print("\t".join([
        f["name"], f["repo"], f["branch"],
        f.get("special", ""),
        " ".join(f.get("prune", [])),
        f.get("mode", "package"),
    ]))
' "$WRT_FEEDS")
