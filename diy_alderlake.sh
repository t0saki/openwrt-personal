cp base.config alderlake.config

echo 'CONFIG_TARGET_OPTIMIZATION="-O2 -march=alderlake -pipe"' >> alderlake.config
echo "CONFIG_TARGET_OPTIONS=y" >> alderlake.config