#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

FEEDS_PATH="./feeds"
PACKAGE_PATH="./package"

#修补命令统一入口：FIX <名称> <守卫目录> <命令...>
#守卫目录不存在时直接跳过，保证在 bash -e 下不中断
FIX() {
	local NAME=$1
	local GUARD=$2
	shift 2

	[ -d "$GUARD" ] || return 0

	echo " "
	if "$@"; then
		echo "$NAME has been fixed!"
	else
		echo "$NAME fix failed; continuing!"
	fi
}

#修改argon主题字体和颜色
FIX "theme-argon" "$PACKAGE_PATH/luci-theme-argon" sed -i \
	"s/primary '.*'/primary '#31a1a1'/g; s/'0.2'/'0.5'/g; s/'none'/'bing'/g; s/'600'/'normal'/g" \
	"$PACKAGE_PATH/luci-theme-argon/luci-app-argon-config/root/etc/config/argon"

LUCKY_VER="${LUCKY_VER:-3.1.3}"
LUCKY_BETA="${LUCKY_BETA:-beta}"
LUCKY_TAG="${LUCKY_TAG:-lucky_docker}"
LUCKY_BASE="https://release.66666.host/v${LUCKY_VER}${LUCKY_BETA}/${LUCKY_VER}_${LUCKY_TAG}"
LUCKY_MK="$(find "$PACKAGE_PATH" -maxdepth 4 -type f -wholename '*/lucky/Makefile' -print -quit 2>/dev/null)"
if [ -f "$LUCKY_MK" ]; then
	echo " "

	sed -i \
		-e "s/^PKG_VERSION:=.*/PKG_VERSION:=$LUCKY_VER/" \
		-e 's#https://github\.com/gdy666/lucky/releases/download/v[$](PKG_VERSION)/\{0,1\}#'"$LUCKY_BASE"'#g' \
		-e 's#_Linux_[$](LUCKY_ARCH)\.tar\.gz#_Linux_$(LUCKY_ARCH)_'"$LUCKY_TAG"'.tar.gz#g' \
		"$LUCKY_MK"

	#兼容tar包内带一层目录的情况，把lucky二进制平铺到编译目录
	awk '
		/(tar|HOST_TAR)/ && /PKG_BUILD_DIR/ && !n {
			print
			print "\t[ -f $(PKG_BUILD_DIR)/lucky ] || find $(PKG_BUILD_DIR) -type f -name lucky -exec mv -f {} $(PKG_BUILD_DIR)/lucky \\;"
			n = 1
			next
		}
		{ print }
	' "$LUCKY_MK" > "$LUCKY_MK.tmp" && mv -f "$LUCKY_MK.tmp" "$LUCKY_MK"

	grep -nE 'PKG_VERSION:=|release\.66666\.host' "$LUCKY_MK"
	echo "lucky has been fixed!"
else
	echo "lucky not found; skipping!"
fi

#修改natmapt菜单位置
FIX "natmapt" "$PACKAGE_PATH/luci-app-natmapt" sed -i "s/network/services/g" \
	"$PACKAGE_PATH/luci-app-natmapt/root/usr/share/luci/menu.d/luci-app-natmap.json"

#修复Rust编译失败
FIX "rust" "$FEEDS_PATH/packages/lang/rust" sed -i 's/ci-llvm=true/ci-llvm=false/g' \
	"$FEEDS_PATH/packages/lang/rust/Makefile"
