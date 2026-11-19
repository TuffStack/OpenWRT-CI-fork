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

# 官方仓库安装：从官方仓库的持久缓存中精确复制需要的包目录到 package/。
# 不注册 src-git、不执行 feeds install -a，避免一个代理 feed 影响其它固件的 Kconfig；
# 也不用整仓复制（package/<repo> 下的二级 Makefile 不会被 OpenWrt 扫描到）。
setup_official_packages() {
	local NAME="$1" REPO="$2" BRANCH="$3" PRUNE="$4" COPY="$5"
	local P
	for P in $PRUNE; do
		find ./feeds -maxdepth 4 -type d -iname "*$P*" -prune -exec rm -rf {} + 2>/dev/null || true
		rm -rf "./package/$P"
	done

	clone_or_update "$REPO" "$BRANCH"
	local SRC="$PKG_SRC_DIR"
	for P in $COPY; do
		[ -f "$SRC/$P/Makefile" ] || { echo "::error::$NAME 官方仓库缺少包目录 $P"; exit 1; }
		rm -rf "./package/$P"
		cp -rf "$SRC/$P" "./package/$P"
	done
	echo "Feed $NAME: 已从官方仓库安装 ${COPY// /, }"
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

# 展开成 | 分隔的记录。| 不是 IFS 空白字符，连续的 || 会保留中间的空字段
# （用 tab 会被 bash read 合并，导致 mode 字段错位、所有包源被判为未知模式）
FEEDS_TSV="$(mktemp)"
python3 -c '
import json, sys
for f in json.loads(sys.argv[1]):
    fields = [
        f["name"], f["repo"], f["branch"],
        f.get("special", ""),
        " ".join(f.get("prune", [])),
        f.get("mode", "package"),
        " ".join(f.get("copy", [])),
    ]
    if any("|" in x for x in fields):
        sys.exit("::error::包源字段含分隔符 |: %r" % (fields,))
    print("|".join(fields))
' "$WRT_FEEDS" > "$FEEDS_TSV" || { echo "::error::展开 WRT_FEEDS 失败"; exit 1; }
[ -s "$FEEDS_TSV" ] || { echo "::error::WRT_FEEDS 展开后为空"; exit 1; }

while IFS='|' read -r F_NAME F_REPO F_BRANCH F_SPECIAL F_PRUNE F_MODE F_COPY; do
	# Windows 本地调试时 Python stdout 会输出 CRLF，去掉行尾 \r 避免模式匹配失败
	F_MODE="${F_MODE%$'\r'}"
	F_COPY="${F_COPY%$'\r'}"
	[ -n "$F_NAME" ] || continue
	case "$F_MODE" in
		package)            UPDATE_PACKAGE "$F_NAME" "$F_REPO" "$F_BRANCH" "$F_SPECIAL" "$F_PRUNE" ;;
		official-packages)  setup_official_packages "$F_NAME" "$F_REPO" "$F_BRANCH" "$F_PRUNE" "$F_COPY" ;;
		*)                  echo "::error::未知包源模式 $F_MODE（$F_NAME）"; exit 1 ;;
	esac
done < "$FEEDS_TSV"
rm -f "$FEEDS_TSV"
