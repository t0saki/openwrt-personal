include $(TOPDIR)/rules.mk

PKG_NAME:=dockerd-router
PKG_VERSION:=1
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only

include $(INCLUDE_DIR)/package.mk

define Package/dockerd-router
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Router-neutral defaults for dockerd
  DEPENDS:=+dockerd
  PKGARCH:=all
endef

define Package/dockerd-router/description
  /etc/docker/daemon.json without docker0, iptables or forwarding changes
  (containers use network_mode: host), and a sysctl override that undoes
  dockerd's bridge-nf-call-ip(6)tables=1. Together with
  patches/0002-dockerd-router-safe-init.patch an installed but unused
  dockerd leaves network, firewall and sysctl exactly as without it.
endef

# Directory, so it ends up in keep.d: the edited data-root and anything else
# put there (certs.d, ...) survive sysupgrade.
define Package/dockerd-router/conffiles
/etc/docker/
endef

define Build/Compile
endef

define Package/dockerd-router/install
	$(INSTALL_DIR) $(1)/etc/docker
	$(INSTALL_DATA) ./files/daemon.json $(1)/etc/docker/daemon.json
	$(INSTALL_DIR) $(1)/etc/sysctl.d
	$(INSTALL_DATA) ./files/13-br-netfilter-off.conf $(1)/etc/sysctl.d/
	$(INSTALL_DIR) $(1)/usr/share/dockerd-router/npm
	$(INSTALL_DATA) ./files/npm/docker-compose.yml $(1)/usr/share/dockerd-router/npm/
endef

$(eval $(call BuildPackage,dockerd-router))
