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

#修改vantage进度条标签字体（anothaDev/luci-theme-vantage#52）
FIX "theme-vantage" "$PACKAGE_PATH/luci-theme-vantage" sed -i \
	-e '/^\/\* progress bars: thin track/,$ { /^\.cbi-progressbar::before {/,/^}/ { s/^[[:space:]]*font: 500 var(--fs-micro)\/1\.2 var(--mono);/\tfont: inherit; line-height: normal;/; } }' \
	"$PACKAGE_PATH/luci-theme-vantage/luci-theme-vantage/htdocs/luci-static/vantage/vantage.css"

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

# dpd-fw 的 luci-app-dpd 把「打开 Honk」按钮写死到 admin/network/proxy，
# 但该节点只在 files/menu-network.json 里定义，Makefile 根本没安装它
# （装进固件的只有 luci-app-dpd.json 的 admin/network/dpd），点按钮必然
# "No page is registered"。honk 自己的 LuCI 页面是 admin/services/honk。
# setup_dpd_feed 用符号链接指向 pkgcache，先实体化再 sed，避免污染缓存源码。
DPD_LUCI="$PACKAGE_PATH/dpd-fw/luci-app-dpd"
DPD_VIEW="$DPD_LUCI/htdocs/luci-static/resources/view/dpd"
if [ -d "$DPD_VIEW" ]; then
	if [ -L "$DPD_LUCI" ]; then
		mkdir -p "$DPD_LUCI.ci"
		cp -rL "$DPD_LUCI/." "$DPD_LUCI.ci/"
		rm -f "$DPD_LUCI"
		mv -f "$DPD_LUCI.ci" "$DPD_LUCI"
	fi
	find "$DPD_VIEW" -maxdepth 1 -type f -name '*.js' -exec \
		sed -i 's|admin/network/proxy|admin/services/honk|g' {} +
	if grep -rq "admin/services/honk" "$DPD_VIEW"; then
		echo "dpd-luci: Honk 按钮已指向 admin/services/honk"
	else
		echo "::warning::dpd-luci 未找到可修补的 Honk 按钮（上游可能已改路径）"
	fi
fi
