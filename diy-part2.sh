# change admin address
sed -i 's/192.168.1.1/192.168.10.10/g' package/base-files/files/bin/config_generate

# change tr3000v1 ubi size
git apply 999-dts-cudy-tr3000-v1-modification.patch

# Copied from https://github.com/Shuery-Shuai/ImmortalWrt-BPI-R4-Firmware/blob/4c275df675faa2d92967a1db4dc96807adef15f3/diy-part2.sh#L210
# Set Rust build arg llvm.download-ci-llvm to false.
RUST_MAKEFILE="feeds/packages/lang/rust/Makefile"
if [[ -f "${RUST_MAKEFILE}" ]]; then
  printf "Modifying %s...\n" "${RUST_MAKEFILE}"
  sed -i 's/--set=llvm\.download-ci-llvm=true/--set=llvm.download-ci-llvm=false/' "${RUST_MAKEFILE}"
else
  echo "File ${RUST_MAKEFILE} does not exist." >&2
fi