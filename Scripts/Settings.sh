#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

#移除luci-app-attendedsysupgrade
sed -i "/attendedsysupgrade/d" $(find ./feeds/luci/collections/ -type f -name "Makefile")
#修改默认主题
sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" $(find ./feeds/luci/collections/ -type f -name "Makefile")
#修改immortalwrt.lan关联IP
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $(find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js")
#添加编译日期标识
STATUS_JS=$(find ./feeds/luci/modules/luci-mod-status/ -type f -name "10_system.js" | head -1)
if [ -n "$STATUS_JS" ]; then
	sed -i -E "s@[+] $' / $WRT_MARK-[0-9.]+-[0-9.:]+'$@@g" "$STATUS_JS"
	sed -i "s/($luciversion || ''$)/(\1) + (' \/ $WRT_MARK-$WRT_DATE')/g" "$STATUS_JS"
	grep -n "luciversion || ''" "$STATUS_JS"
fi

WIFI_SH=$(find ./target/linux/{mediatek/filogic,qualcommax}/base-files/etc/uci-defaults/ -type f -name "*set-wireless.sh" 2>/dev/null)
WIFI_UC="./package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"
if [ -f "$WIFI_SH" ]; then
	#修改WIFI名称
	sed -i "s/BASE_SSID='.*'/BASE_SSID='$WRT_SSID'/g" $WIFI_SH
	#修改WIFI密码
	sed -i "s/BASE_WORD='.*'/BASE_WORD='$WRT_WORD'/g" $WIFI_SH
elif [ -f "$WIFI_UC" ]; then
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

#高通平台调整
DTS_PATH="./target/linux/qualcommax/dts/"
if [[ "${WRT_TARGET^^}" == *"QUALCOMMAX"* ]]; then
	#无WIFI配置调整Q6大小
	if [[ "${WRT_CONFIG,,}" == *"wifi"* && "${WRT_CONFIG,,}" == *"no"* ]]; then
		find $DTS_PATH -type f ! -iname '*nowifi*' -exec sed -i 's/ipq\(6018\|8074\).dtsi/ipq\1-nowifi.dtsi/g' {} +
		echo "qualcommax set up nowifi successfully!"
	fi
fi

#RE-CS-08: 源码 DTS 写死 partname="factory"，本机 GPT 里实际分区名是 "0:ART"
#(lan MAC @0x0, wan MAC @0x6，1MiB，与 DTS 的 fixed-layout 偏移完全吻合)
DTS_FILE="$(find ./target/linux/qualcommbe -name 'ipq5332-re-cs-08.dts' -print -quit 2>/dev/null)"
if [ -n "$DTS_FILE" ] && grep -q 'partname = "factory"' "$DTS_FILE"; then
	sed -i 's/partname = "factory"/partname = "0:ART"/' "$DTS_FILE"
	echo "re-cs-08 partname patched: $DTS_FILE"
	grep -n 'partname' "$DTS_FILE"
else
	echo "re-cs-08 partname already patched or DTS not found"
fi

#RE-CS-08: 内核 FIT 压缩方式 gzip -> lzma
#原因：KERNEL_SIZE=6144k，开启 BTF(daed 依赖) 后 gzip 压缩得到的 uImage.itb 约 7.9MB 超限
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