include $(TOPDIR)/rules.mk

PKG_NAME:=authelia
PKG_VERSION:=4.39.28
PKG_RELEASE:=1

# Official release binary. A source build needs node + pnpm for the web UI on
# top of Go; this one is musl, PIE, CGO sqlite, GOAMD64=v1 and already
# stripped. Before bumping, read the release notes: the example config uses
# webauthn.experimental_enable_passkey_uv_two_factors, which upstream will
# replace and then reject at startup.
PKG_SOURCE:=authelia-v$(PKG_VERSION)-linux-amd64-musl.tar.gz
PKG_SOURCE_URL:=https://github.com/authelia/authelia/releases/download/v$(PKG_VERSION)/
PKG_HASH:=ce2526b633ce3eec06680fae2f26060dc8cef3a92cdbc376410b28bcca6c97e1

PKG_LICENSE:=Apache-2.0

include $(INCLUDE_DIR)/package.mk

# The tarball has no top-level directory.
TAR_CMD=$(HOST_TAR) -C $(1) $(TAR_OPTIONS)
# Ship the verified upstream bytes: sstrip (the musl default) corrupts Go
# binaries, see golang-package.mk.
RSTRIP:=:

define Package/authelia
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Web Servers/Proxies
  TITLE:=Authelia authentication and authorization server
  URL:=https://www.authelia.com
  DEPENDS:=@(x86_64)
  # Fixed ids: dynamic ones are numbered per image (32768 up), and a
  # sysupgrade that restores an older /etc/passwd only appends the names it
  # lacks, so authelia would end up sharing e.g. microsocks' uid/gid from
  # that image. 9091 (the listen port) is unused in the feeds.
  USERID:=authelia=9091:authelia=9091
endef

define Package/authelia/description
  Single sign-on and multi-factor (passkey/WebAuthn, TOTP) portal that
  reverse proxies ask via auth_request whether a request may pass.
  Off until 'uci set authelia.main.enabled=1'; example configs, including
  nginx snippets for LAN-direct/public-auth, are in /usr/share/authelia.
endef

# /etc/authelia/ as a directory ends up in keep.d: users, secrets and the
# database must be restored together (the db is encrypted with the key).
define Package/authelia/conffiles
/etc/config/authelia
/etc/authelia/
endef

define Build/Compile
endef

define Package/authelia/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/authelia $(1)/usr/bin/authelia
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/authelia.init $(1)/etc/init.d/authelia
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/authelia.config $(1)/etc/config/authelia
	$(INSTALL_DIR) $(1)/usr/share/authelia/nginx
	$(INSTALL_DATA) ./files/configuration.yml ./files/users_database.yml \
		$(1)/usr/share/authelia/
	$(INSTALL_DATA) ./files/nginx/*.conf $(1)/usr/share/authelia/nginx/
endef

$(eval $(call BuildPackage,authelia))
