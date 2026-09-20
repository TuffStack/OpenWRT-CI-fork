#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY
#
# qualcommbe 私有补丁失配护栏：上游 bump（如 6.18.52）只批量 rebase 上游侧补丁，
# 分支作者的私有补丁（0609/2008 等）会悬挂导致内核 Patch failed。
# 仅当检测到"坏版本特征"时用仓内 rebase 版（Patches/qualcommbe/）替换；
# 作者在分支上自行修复后特征消失，对应逻辑自动失效。
# 由 WRT-CORE.yml Sync Code 调用，cwd 须为 wrt 源码根目录。

PATCHFIX_DIR="${GITHUB_WORKSPACE:-$PWD}/Patches/qualcommbe"
QBE_PATCHES="target/linux/qualcommbe/patches-6.18"

# 0609: 6.18.52 重构 nf_flow_queue_xmit() 为 struct nf_flow_xmit 签名，
# 坏版本特征：上下文仍引用旧的 tuplehash+type 参数形式
F="$QBE_PATCHES/0609-net-clear-routed-dsa-offload-mark.patch"
if [ -f "$F" ] && grep -q 'const struct flow_offload_tuple_rhash \*tuplehash' "$F"; then
	echo "patchfix: rebasing 0609 onto 6.18.52"
	cp -f "$PATCHFIX_DIR/0609-net-clear-routed-dsa-offload-mark-6.18.52.patch" "$F"
fi

# 2008: 6.18.52 里 qcom_scm_pas_init_image() 参数 peripheral 更名为 pas_id，
# 坏版本特征：插入代码仍使用旧参数名 peripheral
F="$QBE_PATCHES/2008-firmware-qcom_scm-ipq5332-add-support-to-pass-metada.patch"
if [ -f "$F" ] && grep -q '= peripheral;' "$F"; then
	echo "patchfix: rebasing 2008 onto 6.18.52"
	cp -f "$PATCHFIX_DIR/2008-firmware-qcom_scm-ipq5332-add-support-to-pass-metada-6.18.52.patch" "$F"
fi
