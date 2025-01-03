# add lucky
git clone https://github.com/sbwml/packages_lang_golang -b 23.x feeds/packages/lang/golang
git clone https://github.com/gdy666/luci-app-lucky.git package/lucky
make package/lucky/lucky/compile V=s
make package/lucky/luci-app-lucky/compile V=s

# add mosdns
git clone https://github.com/sbwml/luci-app-mosdns -b v5 package/mosdns
git clone https://github.com/sbwml/v2ray-geodata package/v2ray-geodata
make package/mosdns/luci-app-mosdns/compile V=s

