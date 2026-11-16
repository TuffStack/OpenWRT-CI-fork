#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

set -euo pipefail

REPORT_DIR="${GITHUB_WORKSPACE:-$PWD}/build-reports"
mkdir -p "$REPORT_DIR"

git rev-parse HEAD > "$REPORT_DIR/source-commit.txt"
if [ -f .config ]; then
	cp .config "$REPORT_DIR/config.txt"
fi
./scripts/feeds list -fs > "$REPORT_DIR/feeds.buildinfo"

CCACHE_DIR=$(make --no-print-directory -s -f - TOPDIR="$PWD" ci-report-ccache <<'MAKE'
include $(TOPDIR)/rules.mk
.PHONY: ci-report-ccache
ci-report-ccache:
	@printf '%s\n' '$(if $(call qstrip,$(CONFIG_CCACHE_DIR)),$(call qstrip,$(CONFIG_CCACHE_DIR)),$(TOPDIR)/.ccache)'
MAKE
)
export CCACHE_DIR

for TIME_LOG in "$REPORT_DIR"/*.tsv; do
	[ -f "$TIME_LOG" ] || continue
	if [ -f ./scripts/build-time-report.pl ]; then
		./scripts/build-time-report.pl -n 30 "$TIME_LOG" > "${TIME_LOG%.tsv}-report.txt" ||
			echo "Build time report unavailable for $TIME_LOG; raw events retained"
	fi
done

if [ -x ./staging_dir/host/bin/ccache ]; then
	./staging_dir/host/bin/ccache -s > "$REPORT_DIR/ccache.txt"
fi

for GO_BIN in ./staging_dir/hostpkg/bin/go1.*; do
	[ -x "$GO_BIN" ] || continue
	readlink -f "$GO_BIN"
	"$GO_BIN" version
done > "$REPORT_DIR/go-after-build.txt"

if [ -x ./staging_dir/hostpkg/bin/python3 ]; then
	./staging_dir/hostpkg/bin/python3 -c \
		'import sys, sysconfig; print(sys.executable); print(sys.version); print(sysconfig.get_config_var("CONFIG_ARGS"))' \
		> "$REPORT_DIR/python-after-build.txt"
fi
