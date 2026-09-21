#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

FEEDS_PATH="./feeds"
PACKAGE_PATH="./package"

#修改argon主题字体和颜色
if [ -d "$PACKAGE_PATH/luci-theme-argon" ]; then
	echo " "
	if sed -i "s/primary '.*'/primary '#31a1a1'/g; s/'0.2'/'0.5'/g; s/'none'/'bing'/g; s/'600'/'normal'/g" \
		"$PACKAGE_PATH/luci-theme-argon/luci-app-argon-config/root/etc/config/argon"; then
		echo "theme-argon has been fixed!"
	else
		echo "theme-argon fix failed; continuing!"
	fi
fi

#修改aurora菜单式样
if [ -d "$PACKAGE_PATH/luci-app-aurora-config" ]; then
	echo " "
	if find "$PACKAGE_PATH/luci-app-aurora-config/root/usr/share/aurora/" -type f -name '*.template' -exec \
		sed -i "s/nav_type '.*'/nav_type 'dropdown'/g; s/struct_radius_base '.*'/struct_radius_base '0.125rem'/g" {} +; then
		echo "theme-aurora has been fixed!"
	else
		echo "theme-aurora fix failed; continuing!"
	fi
fi

LUCKY_VER="${LUCKY_VER:-3.0.0}"
LUCKY_BETA="${LUCKY_BETA:-beta8}"
LUCKY_TAG="${LUCKY_TAG:-xiaojv_waf}"
LUCKY_BASE="https://release.66666.host/v${LUCKY_VER}${LUCKY_BETA}/${LUCKY_VER}_${LUCKY_TAG}/"
LUCKY_MK="$(find "$PACKAGE_PATH" -maxdepth 4 -type f -wholename '*/lucky/Makefile' -print -quit 2>/dev/null)"
if [ -f "$LUCKY_MK" ]; then
	echo " "

	sed -i \
		-e "s/^PKG_VERSION:=.*/PKG_VERSION:=$LUCKY_VER/" \
		-e 's#https://github\.com/gdy666/lucky/releases/download/v[$](PKG_VERSION)/#'"$LUCKY_BASE"'#g' \
		-e 's#_Linux_[$](LUCKY_ARCH)\.tar\.gz#_Linux_$(LUCKY_ARCH)_'"$LUCKY_TAG"'.tar.gz#g' \
		"$LUCKY_MK"

	#兼容tar包内带一层目录的情况，把lucky二进制平铺到编译目录
	awk '
		/tar -xzvf/ && !n {
			print
			print "\t[ -f $(PKG_BUILD_DIR)/lucky ] || find $(PKG_BUILD_DIR) -type f -name lucky -exec mv -f {} $(PKG_BUILD_DIR)/lucky \\;"
			n = 1
			next
		}
		{ print }
	' "$LUCKY_MK" > "$LUCKY_MK.tmp" && mv -f "$LUCKY_MK.tmp" "$LUCKY_MK"

	grep -nE 'PKG_VERSION:=|release\.66666\.host|xiaojv_waf' "$LUCKY_MK"
	echo "lucky has been fixed!"
else
	echo "lucky not found; skipping!"
fi

#修改natmapt菜单位置
if [ -d "$PACKAGE_PATH/luci-app-natmapt" ]; then
	echo " "
	if sed -i "s/network/services/g" \
		"$PACKAGE_PATH/luci-app-natmapt/root/usr/share/luci/menu.d/luci-app-natmap.json"; then
		echo "natmapt has been fixed!"
	else
		echo "natmapt fix failed; continuing!"
	fi
fi

#修复QModem依赖循环
if [ -d "$PACKAGE_PATH/QModem" ]; then
	echo " "
	if sed -i 's/@!PACKAGE_luci-app-qmodem //g; s/+luci-app-qmodem-next/luci-app-qmodem-next/g' \
		"$PACKAGE_PATH/QModem/luci/luci-app-qmodem-next/Makefile"; then
		echo "QModem has been fixed!"
	else
		echo "QModem fix failed; continuing!"
	fi
fi

#修复Rust编译失败
if [ -d "$FEEDS_PATH/packages/lang/rust" ]; then
	echo " "
	if sed -i 's/ci-llvm=true/ci-llvm=false/g' \
		"$FEEDS_PATH/packages/lang/rust/Makefile"; then
		echo "rust has been fixed!"
	else
		echo "rust fix failed; continuing!"
	fi
fi
