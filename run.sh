#!/bin/bash

# 设置要构建的分支
# branches=("master" "v23.05.3")
branches=("v23.05.3")

# 释放磁盘空间
free_disk_space() {
  echo "Freeing disk space..."
  sudo apt-get purge -y '^dotnet-.*' '^llvm-.*' '^haskell-.*' '^android-.*'
  sudo apt-get autoremove -y
  sudo apt-get clean
  echo "Disk space freed."
}

# 设置构建环境
setup_build_environment() {
  echo "Setting up build environment..."
  sudo apt update
  sudo apt install -y build-essential clang flex bison g++ gawk \
      gcc-multilib g++-multilib gettext git libncurses5-dev libssl-dev \
      python3-setuptools rsync swig unzip zlib1g-dev file wget
  echo "Build environment setup complete."
}

# 克隆 ImmortalWrt 源代码
clone_source_code() {
  local branch=$1
  echo "Cloning ImmortalWrt source code for branch: $branch..."
  git clone -b "$branch" --single-branch --filter=blob:none https://github.com/immortalwrt/immortalwrt
  cd immortalwrt
  echo "Source code cloned."
}

# 复制自定义配置文件
copy_custom_config() {
  echo "Copying custom .config..."
  cp ../../.config .config
  cp ../../build.sh build.sh
  echo ".config copied."
}

# 更新并安装 feeds
update_and_install_feeds() {
  echo "Updating and installing feeds..."
  ./scripts/feeds update -a
  ./scripts/feeds install -a
  echo "Feeds updated and installed."
}

# 构建固件
build_firmware() {
  echo "Building firmware..."
  sh build.sh
  # make -j1 V=s  # 若需详细日志，可启用此行
  echo "Firmware build complete."
}

# 上传构建产物（如有需要）
upload_artifacts() {
  local branch=$1
  echo "Uploading artifacts for branch: $branch..."
  # 假设你有一些本地的脚本或工具来上传构建产物
  # 例如：rsync, scp 或其他类似工具
  # rsync -avh immortalwrt/ /path/to/artifacts/"$branch"/
  echo "Artifacts uploaded."
}

# 创建发布（如有需要）
create_release() {
  local branch=$1
  if [ "$branch" == "master" ]; then
    echo "Creating release for branch: $branch..."
    gh release create "$branch" \
      --title "${branch} Build" \
      --notes "Build of the $branch branch" \
      "immortalwrt/bin/targets/*/*/*"
    echo "Release created."
  fi
}

# 主运行函数
main() {
  # free_disk_space
  # setup_build_environment
  
  for branch in "${branches[@]}"; do
    # 为每个分支创建一个子文件夹
    build_dir="build_${branch}"
    mkdir -p "$build_dir"
    cd "$build_dir"
    
    clone_source_code "$branch"
    copy_custom_config
    update_and_install_feeds
    build_firmware
    # upload_artifacts "$branch"
    # create_release "$branch"
  done
}

# 执行主函数
main