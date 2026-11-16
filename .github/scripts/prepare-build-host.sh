#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

set -euo pipefail

# 宿主机的 Go 只是“能省时间就省”的引导件：不同源码（如大雕 LEDE）未必用到这些配置项，
# runner 上也可能没装工具，探测不到就跳过，不能在这里把整个构建刷掉。
# honk 已改用官方预编译二进制，不再有 Rust/BPF 源码编译，相关主机工具链逻辑已移除。
GO_ROOT=""
if command -v go > /dev/null 2>&1; then
	GO_ROOT=$(go env GOROOT 2>/dev/null || true)
fi

if [ -n "$GO_ROOT" ] && [ -x "$GO_ROOT/bin/go" ]; then
	# Use the runner's Go to bootstrap the feed's pinned host compiler.
	sed -i '/^CONFIG_GOLANG_BUILD_BOOTSTRAP=/d; /^# CONFIG_GOLANG_BUILD_BOOTSTRAP is not set$/d; /^CONFIG_GOLANG_EXTERNAL_BOOTSTRAP_ROOT=/d' .config
	printf '# CONFIG_GOLANG_BUILD_BOOTSTRAP is not set\nCONFIG_GOLANG_EXTERNAL_BOOTSTRAP_ROOT="%s"\n' "$GO_ROOT" >> .config
else
	echo "::warning::宿主机没有可用的 Go，golang 主机引导交回 OpenWrt 处理"
	GO_ROOT=""
fi

# PGO is unnecessary for the build host; keep target Python flags intact.
PGO_STATE="not applicable"
PYTHON_MAKEFILE=feeds/packages/lang/python/python3/Makefile
if [ -f "$PYTHON_MAKEFILE" ]; then
	sed -i '/^HOST_CONFIGURE_ARGS[[:space:]]*+=/,/^$/s/--enable-optimizations/--disable-optimizations/' "$PYTHON_MAKEFILE"
	if ! HOST_PYTHON_ARGS=$(make --no-print-directory -s \
		-C feeds/packages/lang/python/python3 -f Makefile -f - TOPDIR="$PWD" ci-host-python-args <<'MAKE'
.PHONY: ci-host-python-args
ci-host-python-args:
	@printf '%s\n' '$(HOST_CONFIGURE_ARGS)'
MAKE
); then
		echo "::warning::无法展开 python3 的 HOST_CONFIGURE_ARGS，跳过 PGO 检查"
		HOST_PYTHON_ARGS=""
	fi
	case " $HOST_PYTHON_ARGS " in
		*" --enable-optimizations "*)
			PGO_STATE="still enabled"
			echo "::warning::未能关闭主机 Python PGO，主机编译会多花时间，继续构建"
			;;
		*" --disable-optimizations "*)
			PGO_STATE="disabled"
			;;
		# 部分源码的 python3 feed 压根不暴露优化开关，不是错误
		*) ;;
	esac
fi

REPORT_DIR="${GITHUB_WORKSPACE:-$PWD}/build-reports"
mkdir -p "$REPORT_DIR"
{
	if [ -n "$GO_ROOT" ]; then
		"$GO_ROOT/bin/go" version
		printf 'Go bootstrap root: %s\n' "$GO_ROOT"
	else
		printf 'Go bootstrap: not used (no host Go on runner)\n'
	fi
	if [ -n "${HOST_PYTHON_ARGS:-}" ]; then
		printf 'Host Python PGO: %s\n' "$PGO_STATE"
	else
		printf 'Host Python PGO: not applicable\n'
	fi
} | tee "$REPORT_DIR/host-toolchains.txt"
