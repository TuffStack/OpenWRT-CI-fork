#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY
#
# Linux 6.x 的 init/Kconfig 里：
#   config PAHOLE_VERSION
#       int
#       default $(shell,$(srctree)/scripts/pahole-version.sh $(PAHOLE))
# pahole 存在但 --version 输出为空时（最常见是动态链接的 libdw.so.1 找不到），
# $(shell,...) 展开为空，"default" 成了非法语句，oldconfig 直接 syntax error，
# toolchain/kernel-headers 随之失败。
# 这里保证 pahole 要么能报出合法版本号，要么对内核表现为版本 0。
# 注意：这与 BTF 无关，CONFIG_PAHOLE_VERSION 在 Linux 6.x 中无条件求值。
set -uo pipefail

HOST_BIN="$PWD/staging_dir/host/bin"
HOST_LIB="$PWD/staging_dir/host/lib"
LIBDW="$HOST_LIB/libdw.so.1"

# 上一轮兜底可能把真 pahole 换成了 stub。宿主机 libdw1 修好后要能自动恢复，
# 否则 PAHOLE_VERSION 会一直是 0，等于长期禁用 pahole 探测。
if [ -f "$HOST_BIN/pahole" ] && grep -q 'disabled by CI' "$HOST_BIN/pahole" 2>/dev/null; then
	if [ -x "$HOST_BIN/pahole.disabled" ]; then
		mv -f "$HOST_BIN/pahole.disabled" "$HOST_BIN/pahole"
		echo "pahole: 已从上一轮兜底恢复真二进制"
	else
		rm -f "$HOST_BIN/pahole"
		echo "::warning::上一轮 pahole stub 无备份，已删除；请重建 tools/dwarves 以恢复 pahole"
	fi
fi

# make 内部的 PATH 以 staging_dir/host/bin 开头，它比宿主机 /usr/bin/pahole 优先
CANDIDATES=()
[ -x "$HOST_BIN/pahole" ] && CANDIDATES+=("$HOST_BIN/pahole")
if SYS_P="$(command -v pahole 2>/dev/null)" && [ -x "$SYS_P" ]; then
	[ "$SYS_P" = "$HOST_BIN/pahole" ] || CANDIDATES+=("$SYS_P")
fi

if [ "${#CANDIDATES[@]}" -eq 0 ]; then
	echo "pahole: 未安装，内核按 PAHOLE_VERSION=0 处理"
	exit 0
fi

# 只接受 "v1.28" / "1.28" 这类版本号；空输出、动态库报错都算坏
pahole_version() {  # $1=pahole 路径，$2=可选的附加库目录
	local BIN="$1" LIB="${2:-}" OUT
	if [ -n "$LIB" ]; then
		OUT="$(LD_LIBRARY_PATH="$LIB${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" "$BIN" --version 2>/dev/null)" || return 1
	else
		OUT="$("$BIN" --version 2>/dev/null)" || return 1
	fi
	[[ "$OUT" =~ ^v?[0-9]+\.[0-9]+ ]] || return 1
	printf '%s\n' "$OUT"
}

# 只关心 make 真正会调用的那个（PATH 里第一个）
ACTIVE="${CANDIDATES[0]}"
if VER="$(pahole_version "$ACTIVE")"; then
	if [ "$VER" = "v0.0" ]; then
		echo "::warning::pahole 仍被 CI 禁用（$ACTIVE -> $VER），内核按版本 0 处理"
	else
		echo "pahole: $ACTIVE -> $VER"
	fi
	exit 0
fi
echo "::warning::pahole --version 无输出: $ACTIVE（常见原因 libdw.so.1 缺失）"

# 找一个能用的 pahole：原样可用，或补上 OpenWrt host 的 elfutils 库后可用
TARGET=""
WRAP_LIB=""
for BIN in "${CANDIDATES[@]}"; do
	if VER="$(pahole_version "$BIN")"; then
		TARGET="$BIN"
		break
	fi
	if [ -e "$LIBDW" ] && VER="$(pahole_version "$BIN" "$HOST_LIB")"; then
		TARGET="$BIN"
		WRAP_LIB="$HOST_LIB"
		break
	fi
done

mkdir -p "$HOST_BIN"
if [ -n "$TARGET" ]; then
	# host bin 里那个坏二进制先让位，避免 wrapper 把自己当目标
	if [ "$TARGET" = "$HOST_BIN/pahole" ]; then
		mv -f "$TARGET" "$HOST_BIN/pahole.bin"
		TARGET="$HOST_BIN/pahole.bin"
	fi
	if [ -n "$WRAP_LIB" ]; then
		# 只给 pahole 注入库路径，不动全局 LD_LIBRARY_PATH（会污染 git/python 等宿主工具）
		cat > "$HOST_BIN/pahole" <<EOF
#!/bin/sh
LD_LIBRARY_PATH="$WRAP_LIB\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
export LD_LIBRARY_PATH
exec "$TARGET" "\$@"
EOF
	else
		cat > "$HOST_BIN/pahole" <<EOF
#!/bin/sh
exec "$TARGET" "\$@"
EOF
	fi
	chmod +x "$HOST_BIN/pahole"
	if VER="$(pahole_version "$HOST_BIN/pahole")"; then
		echo "pahole: 已修复 $HOST_BIN/pahole -> $VER"
		exit 0
	fi
fi

# 兜底：显式声明 pahole 不可用。--version 返回 v0.0 让 Kconfig 拿到合法整数，
# 其它调用直接失败（不静默产出坏结果）；PAHOLE_VERSION=0 是内核可接受的值。
# 先留一份真二进制，宿主机 libdw1 修好后下一轮可自动恢复。
if [ -f "$HOST_BIN/pahole" ] && ! grep -q 'disabled by CI' "$HOST_BIN/pahole" 2>/dev/null; then
	mv -f "$HOST_BIN/pahole" "$HOST_BIN/pahole.disabled"
fi
cat > "$HOST_BIN/pahole" <<'EOF'
#!/bin/sh
if [ "$1" = "--version" ]; then
	echo "v0.0"
	exit 0
fi
echo "pahole: disabled by CI (libdw.so.1 missing)" >&2
exit 1
EOF
chmod +x "$HOST_BIN/pahole"
if VER="$(pahole_version "$HOST_BIN/pahole")"; then
	echo "::warning::pahole 无法修复，已禁用内核 pahole 探测（按版本 0 处理）: $VER"
	[ -e "$LIBDW" ] || echo "::warning::$LIBDW 也不存在，如需 pahole 请重建 tools/elfutils 或安装宿主机 libdw1"
	exit 0
fi

# 不在这里把构建刷掉：继续跑 make，让日志保留内核的原始报错
echo "::error::pahole 兜底安装失败，请检查 $HOST_BIN 的写权限"
exit 0
