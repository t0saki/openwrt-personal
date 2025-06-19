# change admin address
sed -i 's/192.168.1.1/192.168.10.10/g' package/base-files/files/bin/config_generate

# add date to build info
sed -i 's/IMG_PREFIX:=/IMG_PREFIX:=$(BUILD_DATE_PREFIX)-/g' ./include/image.mk
sed -i '/DTS_DIR:=$(LINUX_DIR)/a\BUILD_DATE_PREFIX := $(shell date +'%F')' ./include/image.mk

# change tr3000v1 ubi size
git apply 999-dts-cudy-tr3000-v1-modification.patch