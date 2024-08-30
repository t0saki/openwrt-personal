#!/bin/bash

make defconfig
cc -v
gcc -v
# sed -i 's/CONFIG_GCC_VERSION="12\.3\.0"/CONFIG_GCC_VERSION="13.1.0"/' .config
cat .config
make -j$(nproc)