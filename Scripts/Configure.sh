#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY
#
# Scripts/Configure.sh —— 唯一的 .config 生成器
# 执行目录：wrt/
#
# 插件控制只有这一处：
#   Config/BASE.txt        平台 / 设备 / 内核（不含包选择项）
#   Config/ENABLE.conf     全局必装（白名单）
#   WRT_PACKAGES           本固件的插件差异（JSON 数组，来自 Config/builds.json）
#   Config/PRIVATE.txt     可选本地覆盖（不入库，最后加载）
#
# 白名单外的"应用层插件"压成 =n；依赖类包（kmod-* / lib* / 核心组件）一律保持
# defconfig 的结果。否则会把 luci-app-xxx 的 DEPENDS 压成 =n，导致打包阶段报
# "依赖的软件包 xxx 在所有仓库都未提供"。

set -euo pipefail

PROFILE="${1:?usage: Configure.sh <profile>}"
CFG_DIR="${GITHUB_WORKSPACE:-$PWD}/Config"
REPORT_DIR="${GITHUB_WORKSPACE:-$PWD}/build-reports"
THEME="${WRT_THEME:-vantage}"
PRIVATE="$CFG_DIR/PRIVATE.txt"
SOURCE_TAG="${WRT_SOURCE:-unknown}"
SOURCE_TAG="${SOURCE_TAG//\//-}"

[ -f "$CFG_DIR/BASE.txt" ] || { echo "::error::缺少 $CFG_DIR/BASE.txt"; exit 1; }
[ -f "$CFG_DIR/ENABLE.conf" ] || { echo "::error::缺少 $CFG_DIR/ENABLE.conf"; exit 1; }
[ -f "$CFG_DIR/builds.json" ] || { echo "::error::缺少 $CFG_DIR/builds.json"; exit 1; }

# 正常由 plan 作业注入；本地单独调试时回退到清单按 profile 取值
if [ -z "${WRT_PACKAGES:-}" ]; then
	BUILDS="$CFG_DIR/builds.json"
	WRT_PACKAGES=$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1],encoding="utf-8"))["profiles"][sys.argv[2]]["packages"]))' "$BUILDS" "$PROFILE")
fi
python3 -c 'import json,sys; d=json.loads(sys.argv[1]); sys.exit(0 if isinstance(d,list) and d else 1)' "$WRT_PACKAGES" \
	|| { echo "::error::WRT_PACKAGES 不是非空 JSON 数组: $WRT_PACKAGES"; exit 1; }

# 清单文件 -> CONFIG_PACKAGE_<pkg>=y；支持 # 注释、空行、@THEME@ 占位符
emit_y() {
	local FILE="$1" LINE PKG
	while IFS= read -r LINE || [ -n "$LINE" ]; do
		PKG="${LINE%%#*}"
		PKG="${PKG//[[:space:]]/}"
		[ -n "$PKG" ] || continue
		PKG="${PKG//@THEME@/$THEME}"
		echo "CONFIG_PACKAGE_${PKG}=y"
	done < "$FILE"
}

# 本固件的插件差异 -> CONFIG_PACKAGE_<pkg>=y
emit_packages() {
	local PKG
	while IFS= read -r PKG; do
		PKG="${PKG//[[:space:]]/}"
		[ -n "$PKG" ] || continue
		echo "CONFIG_PACKAGE_${PKG}=y"
	done < <(python3 -c 'import json,sys; [print(p) for p in json.loads(sys.argv[1])]' "$WRT_PACKAGES")
}

if [ -f "$PRIVATE" ]; then
	echo "Applying private configurations from PRIVATE.txt..."
fi

# 顺序即优先级：平台 -> 全局必装 -> 本固件插件差异 -> 私有覆盖
{
	cat "$CFG_DIR/BASE.txt"
	emit_y "$CFG_DIR/ENABLE.conf"
	emit_packages
	if [ -f "$PRIVATE" ]; then
		cat "$PRIVATE"
	fi
} > .config

# 第 1 遍 defconfig：让上游展开完整符号表（含插件依赖、LEDE 自带包的默认项）
make defconfig -j"$(nproc)"

# 白名单 = 全局必装 + 本固件插件差异 + 私有覆盖里显式 =y 的包
ALLOW="$(mktemp)"
{
	emit_y "$CFG_DIR/ENABLE.conf" | sed 's/^CONFIG_PACKAGE_//; s/=y$//'
	emit_packages | sed 's/^CONFIG_PACKAGE_//; s/=y$//'
	if [ -f "$PRIVATE" ]; then
		grep -oP '^CONFIG_PACKAGE_\K[^=]+(?==y)' "$PRIVATE" || true
	fi
} | sort -u > "$ALLOW"

# 插件候选集 = 所有 profile 的包清单并集（用于压制"其它固件的插件"）
APP_PKGS="$(mktemp)"
python3 -c 'import json,sys; cfg=json.load(open(sys.argv[1],encoding="utf-8")); [print(p) for v in cfg["profiles"].values() for p in v["packages"]]' \
	"$CFG_DIR/builds.json" | sort -u > "$APP_PKGS"

# 归一：只压白名单外的应用层插件（LuCI 应用 / 主题 / 其它固件的插件包）。
# 依赖类包（kmod-netlink-diag、xray-core、dpd-observe 等）保持 =y，
# 由 OpenWrt 的依赖解析决定，绝不在这里动它们。
awk -v allow="$ALLOW" -v apps="$APP_PKGS" '
	BEGIN {
		while ((getline p < allow) > 0) ok[p] = 1
		while ((getline p < apps) > 0) app[p] = 1
	}
	/^CONFIG_PACKAGE_/ && /=y$/ {
		split($0, a, "="); pkg = substr(a[1], 16)   # 去掉 CONFIG_PACKAGE_ 前缀
		if (!(pkg in ok) && (pkg ~ /^luci-app-/ || pkg ~ /^luci-theme-/ || (pkg in app)))
			sub(/=y$/, "=n")
	}
	{ print }
' .config > .config.tmp && mv -f .config.tmp .config

# 第 2 遍 defconfig：依赖重算，被 select 拉回的依赖包自动恢复
make defconfig -j"$(nproc)"

# 白名单校验：两套源码包集合不同，缺失项记录并告警，不直接中止构建
MISSING=""
while IFS= read -r PKG; do
	if grep -Fxq "CONFIG_PACKAGE_${PKG}=y" .config || grep -Fxq "CONFIG_PACKAGE_${PKG}=m" .config; then
		continue
	fi
	MISSING="$MISSING $PKG"
done < "$ALLOW"
mkdir -p "$REPORT_DIR"
if [ -n "$MISSING" ]; then
	echo "::warning::白名单包未进入最终 .config（源码未提供或被依赖关闭）:$MISSING"
	printf '%s\n' $MISSING | sort > "$REPORT_DIR/packages-missing-$SOURCE_TAG-$PROFILE.txt"
fi

# 审计：导出最终进固件的包，报告白名单外的应用层插件（LEDE 漏网项会在这里显形）
REPORT="$REPORT_DIR/packages-$SOURCE_TAG-$PROFILE.txt"
{ grep -oP '^CONFIG_PACKAGE_\K[^=]+(?==y)' .config || true; } | sort -u > "$REPORT"
UNEXPECTED=$(grep -E '^(luci-app-|luci-theme-|mihomo|sing-box|mosdns|lucky|easytier|smartdns|openclash)' "$REPORT" \
	| grep -Fvx -f "$ALLOW" || true)
if [ -n "$UNEXPECTED" ]; then
	echo "::warning::未被清单控制的应用包: $(echo $UNEXPECTED | tr '\n' ' ')"
fi
echo "Configured $(wc -l < "$REPORT") packages (report: $REPORT)"
rm -f "$ALLOW" "$APP_PKGS"
