#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

set -euo pipefail

RUST_FEED="$PWD/feeds/packages/lang/rust"
RUST_MAKEFILE="$RUST_FEED/Makefile"
RUST_VALUES="$RUST_FEED/rust-values.mk"
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPORT_DIR="${GITHUB_WORKSPACE:-$PWD}/build-reports"
mkdir -p "$REPORT_DIR"

# 预编 rust 主机链只是给宿主机省时间，feed 里没有 rust（或结构对不上）时不能把构建卡死，
# 退回 OpenWrt 自己的 rust 主机编译（慢，但能过）
if [ ! -f "$RUST_MAKEFILE" ] || [ ! -f "$RUST_VALUES" ]; then
	echo "::warning::feeds 里没找到 rust feed 的 Makefile/rust-values.mk，跳过 rust 预编工具链"
	exit 0
fi

# Ask the feed for its target triple so CI and OpenWrt use the same mapping.
if ! RUST_TARGET=$(make --no-print-directory -s -f - TOPDIR="$PWD" ci-rust-target <<'MAKE'
include $(TOPDIR)/rules.mk
include $(TOPDIR)/feeds/packages/lang/rust/rust-values.mk
.PHONY: ci-rust-target
ci-rust-target:
	@printf '%s\n' '$(RUSTC_TARGET_ARCH)'
MAKE
); then
	echo "::warning::无法从 rust-values.mk 取得目标三元组，跳过 rust 预编工具链"
	exit 0
fi
RUSTUP_BIN=$(command -v rustup || true)
if [ -z "$RUSTUP_BIN" ]; then
	for candidate in "$HOME/.cargo/bin/rustup" /usr/bin/rustup; do
		if [ -x "$candidate" ]; then RUSTUP_BIN=$candidate; break; fi
	done
fi
if [ -z "$RUSTUP_BIN" ]; then
	echo "::warning::runner 上没装 rustup，回退 OpenWrt 自带的 rust 主机编译（会多花不少时间）"
	exit 0
fi
PATH="$(dirname "$RUSTUP_BIN"):$PATH"
export PATH
RUST_TOOLCHAIN=$(rustup show active-toolchain | awk '{print $1}')
printf 'Rust toolchain: %s\nRust target: %s\n' "$RUST_TOOLCHAIN" "$RUST_TARGET" | tee "$REPORT_DIR/rust-toolchain.txt"

rustup target add --toolchain "$RUST_TOOLCHAIN" "$RUST_TARGET"
RUST_ROOT=$(rustup run "$RUST_TOOLCHAIN" rustc --print sysroot)
test -d "$RUST_ROOT/lib/rustlib/$RUST_TARGET/lib"
for tool in cargo rustc rustdoc; do
	test -x "$RUST_ROOT/bin/$tool"
done

# Replace the source bootstrap before OpenWrt expands its host build rules.
{
	printf 'CI_RUST_ROOT:=%s\n' "$RUST_ROOT"
	cat "$SCRIPT_DIR/rust-prebuilt.mk"
} > "$RUST_FEED/ci-prebuilt.mk"
# shellcheck disable=SC2016 # Match the literal Make expression.
sed -i '/^include \.\/ci-prebuilt.mk$/d; /^$(eval $(call HostBuild))$/i include ./ci-prebuilt.mk' "$RUST_MAKEFILE"
if ! grep -Fxq 'include ./ci-prebuilt.mk' "$RUST_MAKEFILE"; then
	echo "::warning::rust Makefile 里没有 HostBuild 那一行，预编接入失败，回退源码编译"
	exit 0
fi

"$RUST_ROOT/bin/rustc" --version | tee -a "$REPORT_DIR/rust-toolchain.txt"
echo "Using runner Rust $RUST_TOOLCHAIN for $RUST_TARGET" | tee -a "$REPORT_DIR/rust-toolchain.txt"
sha256sum "$RUST_MAKEFILE" >> "$REPORT_DIR/rust-toolchain.txt"
