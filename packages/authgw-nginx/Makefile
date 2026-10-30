include $(TOPDIR)/rules.mk

PKG_NAME:=authgw-nginx
PKG_VERSION:=1
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only

include $(INCLUDE_DIR)/package.mk

define Package/authgw-nginx
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Web Servers/Proxies
  TITLE:=Inert nginx base config for the Authelia gateway
  DEPENDS:=+nginx-full
  PKGARCH:=all
endef

define Package/authgw-nginx/description
  Replaces nginx-ssl-util's stock UCI servers (self-signed '_lan' on :443,
  '_redirect2ssl' on :80) with a plain /etc/nginx/nginx.conf that listens
  nowhere until /etc/nginx/conf.d/*.conf adds a server. Leaves uhttpd alone.
endef

define Package/authgw-nginx/conffiles
/etc/nginx/nginx.conf
endef

define Build/Compile
endef

define Package/authgw-nginx/install
	$(INSTALL_DIR) $(1)/etc/nginx
	$(INSTALL_DATA) ./files/nginx.conf $(1)/etc/nginx/nginx.conf
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/authgw-nginx.uci-defaults $(1)/etc/uci-defaults/60-authgw-nginx
endef

$(eval $(call BuildPackage,authgw-nginx))
