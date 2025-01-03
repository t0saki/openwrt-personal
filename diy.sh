# add lucky
git clone https://github.com/sbwml/packages_lang_golang -b 23.x feeds/packages/lang/golang
git clone https://github.com/gdy666/luci-app-lucky.git package/lucky
make package/lucky/lucky/compile V=s
make package/lucky/luci-app-lucky/compile V=s

# add mosdns
git clone https://github.com/sbwml/luci-app-mosdns -b v5 package/mosdns
git clone https://github.com/sbwml/v2ray-geodata package/v2ray-geodata
make package/mosdns/luci-app-mosdns/compile V=s

# change admin address
sed -i 's/192.168.1.1/192.168.10.10/g' package/base-files/files/bin/config_generate

# add date to build info
sed -i 's/IMG_PREFIX:=/IMG_PREFIX:=$(BUILD_DATE_PREFIX)-/g' ./include/image.mk
sed -i '/DTS_DIR:=$(LINUX_DIR)/a\BUILD_DATE_PREFIX := $(shell date +'%F')' ./include/image.mk