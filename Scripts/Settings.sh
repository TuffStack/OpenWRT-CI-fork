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
#注：feeds 每次构建都会 git checkout 还原 10_system.js，故直接注入即可（无需去重）
STATUS_JS=$(find ./feeds/luci/modules/luci-mod-status/ -type f -name "10_system.js" | head -1)
if [ -n "$STATUS_JS" ]; then
	#在 (luciversion || '') 之后追加 " / 标记-日期"；用 # 作分隔符避免转义斜杠，且不使用反向引用
	sed -i "s#(luciversion || '')#(luciversion || '') + (' / ${WRT_MARK}-${WRT_DATE}')#g" "$STATUS_JS"
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
DTS_FILE="$(find ./target/linux/qualcommbe -name 'ipq5332-re-cs-08.dts' -print -quit 2>/dev/null)"
if [ -n "$DTS_FILE" ] && grep -q 'partname = "factory"' "$DTS_FILE"; then
	sed -i 's/partname = "factory"/partname = "0:ART"/' "$DTS_FILE"
	echo "re-cs-08 partname patched: $DTS_FILE"
	grep -n 'partname' "$DTS_FILE"
else
	echo "re-cs-08 partname already patched or DTS not found"
fi

#RE-CS-08: SFP(WAN) 猫棒 2500base-x 链路无法 up 的规避
#根因：上游内核 phylink/SFP 变更后，sfp 端口 managed="in-band-status" 会让 phylink
#以 in-band(带内自协商) 方式配置 2500base-x；而高通 PCS 对 2500BASEX 仅允许禁用带内，
#于是报 "autoneg setting not compatible with PCS"，链路反复重配且永不 carrier up，
#导致无法拨号(与 openwrt#21434 同族回归；DTS 未变、纯内核 bump 触发)。
#规避：把 sfp 端口改成像同级 switch 端口那样的 fixed-link(2500 全双工)，绕开带内协商。
#代价：失去 SFP 框架的模块 EEPROM/DDMI 在位管理(对常驻猫棒无影响)，换取 WAN 正常链路。
if [ -n "$DTS_FILE" ] && grep -q 'ppe_sfp' "$DTS_FILE" \
	&& grep -q 'managed = "in-band-status"' "$DTS_FILE"; then
	#1) 删除 in-band 自协商与 sfp 句柄两行；2) 在 ppe_sfp 节点收尾 }; 之前插入 fixed-link 子节点
	#  (DTC 要求属性必须排在子节点之前，故 fixed-link 必须放在节点所有属性之后)
	sed -i -e '/^[[:space:]]*managed = "in-band-status";[[:space:]]*$/d' \
		-e '/^[[:space:]]*sfp = <&sfp0>;[[:space:]]*$/d' "$DTS_FILE"
	awk '
		BEGIN{ inblk=0; depth=0 }
		{
			if(!inblk){
				print
				if($0 ~ /ppe_sfp: port@2/){ inblk=1; depth=1 }
				next
			}
			tmp=$0
			o=gsub(/\{/,"{",tmp); c=gsub(/\}/,"}",tmp)
			depth += o - c
			if(depth<=0){
				print "\t\t\tfixed-link {"
				print "\t\t\t\tspeed = <2500>;"
				print "\t\t\t\tfull-duplex;"
				print "\t\t\t};"
				print
				inblk=0
				next
			}
			print
		}
	' "$DTS_FILE" > "$DTS_FILE.tmp" && mv -f "$DTS_FILE.tmp" "$DTS_FILE"
	echo "re-cs-08 SFP patched to fixed-link (in-band autoneg workaround)"
	grep -n -A30 'ppe_sfp: port@2' "$DTS_FILE"
else
	echo "re-cs-08 SFP already fixed-link or pattern not found; skipping"
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

