#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

set -euo pipefail

I2C_MAKEFILE=feeds/packages/utils/i2c-tools/Makefile
if [ ! -f "$I2C_MAKEFILE" ]; then
	echo "::warning::i2c-tools 不在 feeds/packages 中，跳过 python-smbus 修补"
	exit 0
fi

# Build the Python SMBus binding only when its package is selected. The C
# tools remain available for device profiles that only install i2c-tools.
if ! grep -Fqx 'PKG_CONFIG_DEPENDS:=CONFIG_PACKAGE_python3-smbus' "$I2C_MAKEFILE"; then
	#下面的补丁按固定排版逐行匹配，换源码(如大雕 LEDE)后排版可能对不上；
	#半命中的 sed 会把 feed 改成四不像，再被末尾校验直接干掉整个构建，所以先探测再动手
	if ! grep -Fxq 'PKG_BUILD_DEPENDS:=python-setuptools/host' "$I2C_MAKEFILE" ||
	   ! grep -Fxq $'\t$(call Py3Build/Compile)' "$I2C_MAKEFILE"; then
		echo "::warning::i2c-tools Makefile 排版与补丁模板不一致，跳过 python-smbus 修补"
		exit 0
	fi

	# Keep the Make expressions literal; they are intentionally not shell-expanded.
	# shellcheck disable=SC2016
	sed -i \
		-e 's/^PKG_BUILD_DEPENDS:=python-setuptools\/host$/PKG_CONFIG_DEPENDS:=CONFIG_PACKAGE_python3-smbus\nPKG_BUILD_DEPENDS:=PACKAGE_python3-smbus:python-setuptools\/host/' \
		-e 's/^\t$(call Py3Build\/Compile)$/\t$(if $(CONFIG_PACKAGE_python3-smbus),$(call Py3Build\/Compile))/' \
		-e 's/^\t$(call Py3Build\/Install)$/\t$(if $(CONFIG_PACKAGE_python3-smbus),$(call Py3Build\/Install))/' \
		-e 's/^  DEPENDS:=+libi2c +python3-light$/  DEPENDS:=+libi2c +PACKAGE_python3-smbus:python3-light/' \
		"$I2C_MAKEFILE"
fi

grep -Fqx 'PKG_CONFIG_DEPENDS:=CONFIG_PACKAGE_python3-smbus' "$I2C_MAKEFILE"
grep -Fqx 'PKG_BUILD_DEPENDS:=PACKAGE_python3-smbus:python-setuptools/host' "$I2C_MAKEFILE"
grep -Fqx '  DEPENDS:=+libi2c +PACKAGE_python3-smbus:python3-light' "$I2C_MAKEFILE"
grep -Fqx $'\t$(if $(CONFIG_PACKAGE_python3-smbus),$(call Py3Build/Compile))' "$I2C_MAKEFILE"
grep -Fqx $'\t$(if $(CONFIG_PACKAGE_python3-smbus),$(call Py3Build/Install))' "$I2C_MAKEFILE"
