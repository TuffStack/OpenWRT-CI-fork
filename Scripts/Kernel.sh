#!/bin/bash
# SPDX-License-Identifier: MIT
# Scripts/Kernel.sh —— 打开 内核选项
# 执行目录：wrt/

set -e

# ===== Docker 原生内核符号（全局注入）=====
# 定位最后一个存在的配置片段（后写覆盖先写）
BOARD="$(grep -m1 -oP '^CONFIG_TARGET_\K[a-z0-9]+(?==y)' ./.config)"
[ -n "$BOARD" ] || { echo "kernel: 无法识别 target"; exit 1; }

KPATCH="$(grep -m1 -oP '^KERNEL_PATCHVER:=\K.*' "target/linux/$BOARD/Makefile" 2>/dev/null || true)"
if [ -z "$KPATCH" ]; then
	KPATCH="$(grep -m1 -oP '^KERNEL_TESTING_PATCHVER:=\K.*' "target/linux/$BOARD/Makefile" 2>/dev/null || true)"
fi
if [ -z "$KPATCH" ]; then
	KPATCH="$(grep -m1 -oP '^KERNEL_PATCHVER:=\K.*' target/linux/generic/Makefile 2>/dev/null || true)"
fi
[ -n "$KPATCH" ] || { echo "kernel: 无法识别 KERNEL_PATCHVER"; exit 1; }

SUBTARGET="$(grep -m1 -oP "^CONFIG_TARGET_${BOARD}_\K[\w]+(?=\=y)" ./.config)"

KCONF=""
for f in "target/linux/generic/config-$KPATCH" \
         "target/linux/$BOARD/config-$KPATCH" \
         "target/linux/$BOARD/$SUBTARGET/config-$KPATCH"; do
	[ -f "$f" ] && KCONF="$f"
done
[ -n "$KCONF" ] || { echo "kernel: 找不到内核配置片段"; exit 1; }

while IFS= read -r LINE; do
	NAME="${LINE%%=*}"
	if grep -qE "^${NAME}=|^# ${NAME} is not set" "$KCONF"; then
		sed -i "s|^${NAME}=.*|${LINE}|; s|^# ${NAME} is not set|${LINE}|" "$KCONF"
	else
		echo "$LINE" >> "$KCONF"
	fi
done <<'EOF'
CONFIG_NAMESPACES=y
CONFIG_UTS_NS=y
CONFIG_IPC_NS=y
CONFIG_PID_NS=y
CONFIG_NET_NS=y
CONFIG_USER_NS=y
CONFIG_CGROUP_FREEZER=y
CONFIG_CPUSETS=y
CONFIG_CGROUP_DEVICE=y
CONFIG_CGROUP_SCHED=y
CONFIG_POSIX_MQUEUE=y
CONFIG_SECCOMP=y
CONFIG_SECCOMP_FILTER=y
CONFIG_BRIDGE=y
CONFIG_BRIDGE_NETFILTER=y
CONFIG_OVERLAY_FS=y
CONFIG_MACVLAN=y
EOF
echo "kernel: 容器原生内核符号已统一写入 $KCONF"
