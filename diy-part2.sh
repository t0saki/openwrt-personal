# change admin address
sed -i 's/192.168.1.1/192.168.10.10/g' package/base-files/files/bin/config_generate

# change tr3000v1 ubi size
git apply 999-dts-cudy-tr3000-v1-modification.patch
