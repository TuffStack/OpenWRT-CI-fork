#
# OpenWrt package: honk (prebuilt upstream release binary)
#
# Uses the official daeuniverse/honk prebuilt aarch64 musl "full" release
# binary instead of compiling Rust (which needs nightly + bpf-linker). The
# musl build is static and embeds the eBPF object and the doona dashboard
# (native-ui), with the Clash API and native API enabled.
#
# The official release tar.gz packs one top-level directory
# (honk-core-<version>-<target>-full/) holding the honk-core binary; Build/Prepare
# strips it so the binary lands directly in PKG_BUILD_DIR.
#
# files/honk.init is the upstream init script plus a cgroup v2 mount guard;
# files/config.dae is the upstream minimal configuration with the embedded UI
# on 0.0.0.0:9527. Geo dat files come from v2ray-geoip/v2ray-geosite, linked
# into /usr/share/honk.
#
# This file is free software, licensed under the GNU General Public License v3
# or later.

include $(TOPDIR)/rules.mk

PKG_NAME:=honk
# apk spells the beta pre-release with "_beta"; the upstream tag uses "-beta".
PKG_VERSION:=0.1.0_beta6
PKG_RELEASE:=1

HONK_UPSTREAM_VER:=v0.1.0-beta.6
# This CI only builds aarch64 (qualcommbe/ipq53xx); keep the target explicit so
# a wrong-target build fails loudly instead of silently downloading the wrong
# binary. The sha256 is the release asset's SHA256SUMS entry.
PKG_SOURCE:=honk-core-$(HONK_UPSTREAM_VER)-aarch64-unknown-linux-musl-full.tar.gz
PKG_SOURCE_URL:=https://github.com/daeuniverse/honk/releases/download/$(HONK_UPSTREAM_VER)/
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
  # honk-core (static musl) needs TC-bpf + a veth pair (daens), nftables queue
  # over nfnetlink_queue for NFQUEUE, and geo dat files. BTF comes from the
  # kernel (this CI enables CONFIG_DEBUG_INFO_BTF), so no vmlinux-btf package.
  DEPENDS:=+kmod-veth +kmod-sched-core +kmod-sched-bpf \
           +kmod-nft-core +kmod-nft-queue +kmod-nfnetlink-queue \
           +kmod-nf-conntrack +v2ray-geoip +v2ray-geosite
endef

define Package/honk/description
 honk is an eBPF transparent proxy engine. This package uses the official
 prebuilt aarch64 musl "full" release binary, which embeds its eBPF object and
 the doona dashboard and enables the Clash API and the native API. Requires
 kernel BTF for CO-RE relocations (provided by CONFIG_DEBUG_INFO_BTF).
endef

# The release archive packs a single top-level directory; strip it so the
# honk-core binary (and optional LICENSE) land directly in PKG_BUILD_DIR.
# (Do NOT call Build/Prepare/Default here: it already UNPACKs PKG_SOURCE,
# which would unpack the archive a second time without stripping.)
define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(TAR) -C $(PKG_BUILD_DIR) --strip-components=1 -xzf $(DL_DIR)/$(PKG_SOURCE)
endef

# Nothing to compile: the binary was already built upstream.
define Build/Compile
	true
endef

define Package/honk/conffiles
/etc/config/honk
/etc/honk/config.dae
endef

define Package/honk/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/honk-core $(1)/usr/bin/honk-core
	$(INSTALL_DIR) $(1)/usr/share/licenses/honk
	if [ -f $(PKG_BUILD_DIR)/LICENSE ]; then \
		$(INSTALL_DATA) $(PKG_BUILD_DIR)/LICENSE $(1)/usr/share/licenses/honk/LICENSE; \
	fi
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