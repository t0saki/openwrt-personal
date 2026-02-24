# add lucky
git clone https://github.com/gdy666/luci-app-lucky.git package/lucky

# add mosdns
git clone https://github.com/sbwml/packages_lang_golang -b 26.x feeds/packages/lang/golang
git clone https://github.com/sbwml/luci-app-mosdns -b v5 package/mosdns
git clone https://github.com/sbwml/v2ray-geodata package/v2ray-geodata

# add string to build info
BUILD_DATE=$(date +'%Y%m%d')
PERSONAL_ID="tosaki"
echo "CONFIG_EXTRA_IMAGE_NAME=\"${EXTRA_NAME}\"" >> .config
