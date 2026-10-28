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
echo "CONFIG_PACKAGE_luci-app-$WRT_THEME=y" >> ./.config
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

	#RE-CS-08: SFP 口(ppe_sfp)改为 fixed-link 2500base-x
	if grep -q 'ppe_sfp: port@2' "$DTS_FILE"; then
		if sed -n '/ppe_sfp: port@2 {/,/};/p' "$DTS_FILE" | grep -q 'fixed-link'; then
			echo "re-cs-08 sfp: fixed-link already present; skipping"
		else
			#1) 节点范围内(缩进容错)：删 in-band 与 sfp 句柄，phy-mode 固定 2500base-x
			sed -i '/ppe_sfp: port@2 {/,/};/{
				/^[[:space:]]*managed = "in-band-status";[[:space:]]*$/d
				/^[[:space:]]*qcom,sfp-force-sgmii/d
				/^[[:space:]]*sfp = <&sfp0>;[[:space:]]*$/d
				s/phy-mode = "[^"]*"/phy-mode = "2500base-x"/
			}' "$DTS_FILE"

			#2) 按花括号深度找到节点自身的收尾 };，在其前一行插入 fixed-link；
			#   缩进由收尾行推导，不硬写 Tab 个数
			awk '
				BEGIN { inblk = 0; depth = 0 }
				{
					if (!inblk) {
						print
						if ($0 ~ /ppe_sfp: port@2/) { inblk = 1; depth = 1 }
						next
					}
					buf = $0
					depth += gsub(/\{/, "{", buf) - gsub(/\}/, "}", buf)
					if (depth <= 0) {
						match($0, /^[ \t]*/)
						ind = substr($0, 1, RLENGTH) "\t"
						print ind "fixed-link {"
						print ind "\tspeed = <2500>;"
						print ind "\tfull-duplex;"
						print ind "};"
						inblk = 0
					}
					print
				}
			' "$DTS_FILE" > "$DTS_FILE.tmp" && mv -f "$DTS_FILE.tmp" "$DTS_FILE"

			#3) 校验：phy-mode 与 fixed-link 都必须落在节点内，否则显式报错不假装成功
			#   (区间回显会在 fixed-link 自身 }; 处截断，故只用于校验，展示用 grep -A)
			NODE_TXT="$(sed -n '/ppe_sfp: port@2 {/,/};/p' "$DTS_FILE")"
			if grep -q 'fixed-link' <<<"$NODE_TXT" && grep -q 'phy-mode = "2500base-x"' <<<"$NODE_TXT"; then
				echo "re-cs-08 sfp: patched to fixed-link 2500base-x"
			else
				echo "::error::re-cs-08 sfp patch FAILED (DTS layout changed); 光口仍会不起链，请检查 ppe_sfp 节点排版"
			fi
			grep -n -A28 'ppe_sfp: port@2' "$DTS_FILE"
		fi
	else
		echo "::warning::re-cs-08 ppe_sfp node not found; sfp patch SKIPPED"
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
