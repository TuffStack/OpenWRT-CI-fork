#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

#移除luci-app-attendedsysupgrade
find ./feeds/luci/collections/ -type f -name "Makefile" -exec sed -i "/attendedsysupgrade/d" {} +
#修改默认主题
find ./feeds/luci/collections/ -type f -name "Makefile" -exec sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" {} +
#修改immortalwrt.lan关联IP
find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js" -exec sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" {} +
#添加编译日期标识
find ./feeds/luci/modules/luci-mod-status/ -type f -name "10_system.js" -exec sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ $WRT_MARK-$WRT_DATE')/g" {} +

WIFI_UC="./package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"
if [ -f "$WIFI_UC" ]; then
	#修改WIFI名称
	sed -i "s/ssid='.*'/ssid='$WRT_SSID'/g" $WIFI_UC
	#修改WIFI密码
	sed -i "s/key='.*'/key='$WRT_WORD'/g" $WIFI_UC
fi

CFG_FILE="./package/base-files/files/bin/config_generate"
#修改默认IP地址
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $CFG_FILE
#修改默认主机名
sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" $CFG_FILE

#配置文件修改
echo "CONFIG_PACKAGE_luci=y" >> ./.config
echo "CONFIG_LUCI_LANG_zh_Hans=y" >> ./.config
echo "CONFIG_PACKAGE_luci-theme-$WRT_THEME=y" >> ./.config
echo "CONFIG_PACKAGE_luci-app-$WRT_THEME-config=y" >> ./.config

#引入私有扩展配置
if [ -f "$GITHUB_WORKSPACE/Config/PRIVATE.txt" ]; then
	echo "Applying private configurations from PRIVATE.txt..."
	cat $GITHUB_WORKSPACE/Config/PRIVATE.txt >> ./.config
fi

#手动调整的插件
if [ -n "$WRT_PACKAGE" ]; then
	echo -e "$WRT_PACKAGE" >> ./.config
fi

#无WIFI配置标志
if [[ "${WRT_CONFIG,,}" == *"wifi"* && "${WRT_CONFIG,,}" == *"no"* ]]; then
	echo "WRT_WIFI=wifi-no" >> $GITHUB_ENV
fi

#RE-CS-08: 源码 DTS 写死 partname="factory"，本机 GPT 里实际分区名是 "0:ART"
#(lan MAC @0x0, wan MAC @0x6，1MiB，与 DTS 的 fixed-layout 偏移完全吻合)
DTS_FILE="$(find ./target/linux/qualcommbe -name '*re-cs-08.dts' -print -quit 2>/dev/null)"
if [ -z "$DTS_FILE" ]; then
	echo "::warning::re-cs-08 DTS not found; partname patch SKIPPED (MAC may read wrong partition)"
else
	if grep -q 'partname = "factory"' "$DTS_FILE"; then
		sed -i 's/partname = "factory"/partname = "0:ART"/' "$DTS_FILE"
		echo "re-cs-08 partname patched: $DTS_FILE"
	else
		echo "re-cs-08 partname already patched: $DTS_FILE"
	fi

	#RE-CS-08: 本机实装 SFP 为 ONT 光猫棒(ALCATELLUCENT 3FE46541AA)，主机侧固定 2.5G。
	#源码 DTS 为匹配 10G SFP+ 工厂模块，把 ppe_sfp 口改为 10gbase-r + in-band-status，
	#导致本 2.5G 棒回归失效，两处一并改回（硬件固定属性，速率写死不走 workflow）：
	#  1) phy-mode 10gbase-r -> 2500base-x：否则 phylink 按 10000 选接口报
	#     "selection of interface failed, speed 10000"，光口起不了链。
	#  2) managed in-band-status -> fixed-status：本棒不做标准 AN，in-band 会触发
	#     "autoneg setting not compatible with PCS" 且 PCS 锁不上(pcs-link=0)。运行时
	#     ethtool -s autoneg off 会被 phylink 按 inband 覆盖，故必须改 DTS 重编。
	if grep -qE 'phy-mode = "10gbase-r"|managed = "in-band-status"' "$DTS_FILE"; then
		sed -i -e 's/phy-mode = "10gbase-r"/phy-mode = "2500base-x"/' \
			-e 's/managed = "in-band-status"/managed = "fixed-status"/' "$DTS_FILE"
		echo "re-cs-08 sfp patched: phy-mode -> 2500base-x, managed -> fixed-status"
		grep -nE 'phy-mode|managed' "$DTS_FILE"
	else
		echo "re-cs-08 sfp phy-mode already patched or 10gbase-r not found: $DTS_FILE"
	fi
fi

#RE-CS-08: 内核 FIT 压缩方式 gzip -> lzma
#原因：KERNEL_SIZE=6144k，gzip 压缩得到的 uImage.itb 可能超限，改用 lzma 进一步压缩体积
if [[ "${WRT_TARGET^^}" == *"QUALCOMMBE"* ]]; then
	IPQ53XX_MK="./target/linux/qualcommbe/image/ipq53xx.mk"
	if [ -f "$IPQ53XX_MK" ] && grep -q '^define Device/jdcloud_re-cs-08$' "$IPQ53XX_MK"; then
		sed -i '\#^define Device/jdcloud_re-cs-08$#,\#^endef$#s|call Device/FitImage)|call Device/FitImageLzma)|' "$IPQ53XX_MK"
		echo "qualcommbe: re-cs-08 FIT compression -> lzma"
		grep -n -A2 '^define Device/jdcloud_re-cs-08$' "$IPQ53XX_MK"
	else
		echo "qualcommbe: ipq53xx.mk or jdcloud_re-cs-08 not found; skipping"
	fi
fi
