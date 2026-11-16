#
# OpenWrt package: honk (prebuilt upstream release binary)
#
# Instead of compiling honk-core from Rust (as daeuniverse/openwrt-packages
# does), this package downloads the official prebuilt release binary. That is
# the aarch64 musl "full" variant, which embeds the eBPF object and the doona
# dashboard (native-ui) and enables the clash-api, jemalloc, rprx, ebpf and
# native-api features. This keeps the build fast and independent of the Rust
# toolchain, at the cost of pinning the binary to one upstream release.
#
# files/honk.init is the upstream init script plus a cgroup v2 mount guard
# (the upstream script only enables the memory controller, assuming cgroup2 is
# already mounted; see nodes below). files/config.dae is the upstream minimal
# configuration with the embedded UI on 0.0.0.0:9527.
#
# The geo dat files come from v2ray-geoip / v2ray-geosite (the v2ray-geodata
# feed); this package links them into /usr/share/honk, which honk searches
# before the dae locations.
#
# This file is free software, licensed under the GNU General Public License v3
# or later.

include $(TOPDIR)/rules.mk

PKG_NAME:=honk
# apk spells the beta pre-release with "_beta"; the upstream tag uses "-beta".
PKG_VERSION:=0.1.0_beta6
PKG_RELEASE:=1

HONK_UPSTREAM_VER:=v0.1.0-beta.6
# This CI only builds aarch64 (qualcommbe/ipq53xx). The upstream archive name
# is architecture-specific; keep it explicit so a wrong-target build fails
# loudly instead of silently downloading the wrong binary.
PKG_SOURCE:=honk-core-$(HONK_UPSTREAM_VER)-aarch64-unknown-linux-musl-full.tar.gz
PKG_SOURCE_URL:=https://github.com/daeuniverse/honk/releases/download/$(HONK_UPSTREAM_VER)/
# TODO: fill in the real sha256 from the upstream release once `make download`
# reports it (OpenWrt prints the hash on first download). "skip" disables the
# check only for this first build, which is unsafe to keep long-term.
PKG_HASH:=skip

PKG_LICENSE:=GPL-3.0-only
PKG_LICENSE_FILES:=LICENSE

include $(INCLUDE_DIR)/package.mk

define Package/honk
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Web Servers/Proxies
  TITLE:=eBPF transparent proxy engine (honk-core) with embedded UI
  URL:=https://github.com/daeuniverse/honk
  LICENSE:=GPL-3.0-only
  # honk-core is linked against OpenWrt's musl and C++ runtime. Its eBPF
  # datapath needs TC-bpf and a veth pair (daens), and its NFQUEUE staging uses
  # nftables queue expressions over nfnetlink_queue. BTF comes from the kernel
  # (this CI enables CONFIG_DEBUG_INFO_BTF), so no vmlinux-btf package is
  # required. geoip/geosite ship the .dat files.
  DEPENDS:=+libstdcpp +kmod-veth +kmod-sched-core +kmod-sched-bpf \
           +kmod-nft-core +kmod-nft-queue +kmod-nfnetlink-queue \
           +kmod-nf-conntrack +v2ray-geoip +v2ray-geosite
endef

define Package/honk/description
 honk is an eBPF transparent proxy engine. This package uses the official
 prebuilt aarch64 musl "full" release binary, which embeds its eBPF object and
 the doona dashboard and enables the Clash API and the native API. Requires
 kernel BTF for CO-RE relocations (provided by CONFIG_DEBUG_INFO_BTF).
endef

# The release archive may unpack with or without a leading directory; locate
# the binary and flatten it into $(PKG_BUILD_DIR)/honk-core.
define Build/Compile
	find $(PKG_BUILD_DIR) -maxdepth 3 -type f -name 'honk-core' \
		-exec cp -f {} $(PKG_BUILD_DIR)/honk-core \;
	[ -x $(PKG_BUILD_DIR)/honk-core ] || \
		{ echo "honk: honk-core not found in $(PKG_SOURCE)"; exit 1; }
endef

define Package/honk/conffiles
/etc/config/honk
/etc/honk/config.dae
endef

define Package/honk/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/honk-core $(1)/usr/bin/honk-core
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/honk.init $(1)/etc/init.d/honk
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/honk.config $(1)/etc/config/honk
	$(INSTALL_DIR) $(1)/etc/honk
	$(INSTALL_CONF) ./files/config.dae $(1)/etc/honk/config.dae
	$(INSTALL_DIR) $(1)/lib/upgrade/keep.d
	printf '%s\n' '/etc/honk/data/' > $(1)/lib/upgrade/keep.d/honk
	# v2ray-geoip/geosite install under /usr/share/v2ray; honk looks in
	# /usr/share/honk before /usr/share/dae.
	$(INSTALL_DIR) $(1)/usr/share/honk
	$(LN) ../v2ray/geoip.dat $(1)/usr/share/honk/geoip.dat
	$(LN) ../v2ray/geosite.dat $(1)/usr/share/honk/geosite.dat
endef

$(eval $(call BuildPackage,honk))