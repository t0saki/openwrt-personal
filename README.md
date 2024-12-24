# OpenWRT Personal Build Workflow

本项目提供了一种自动化构建 OpenWRT 固件的工作流，用户可以通过修改配置文件和分支选择生成自定义的 OpenWRT 固件。目前该项目构建ImmortalWrt分支，可直接在release下载并遵循当地法律法规使用。

## 分支和配置说明

- **分支**: 
  - `openwrt-24.10`: 24.10的SNAPSHOT分支。
  - `v24.10.0-rc2`: ImmortalWrt的相应Tag。
  
- **配置文件**:
  - `base.config`: 适用于大部分x86设备的配置，包含许多常用插件。默认使用2G分区防止容量不足。
  - `alderlake.config`: 适用于Alderlake架构构建的配置，使用O2优化，其余配置与base一致。

## 如何使用

### 1. 修改构建分支和配置
根据需求，编辑 [`.github/workflows/build-openwrt.yml`](https://github.com/t0saki/openwrt-personal/blob/main/.github/workflows/build-openwrt.yml) 文件。在以下部分指定需要构建的分支和配置文件：

env:
  BRANCH: [选择目标分支，例如 openwrt-24.10]
  CONFIG: [选择配置文件，例如 base.config 或 alderlake.config]

2. 定制配置文件

根据 OpenWRT 或 ImmortalWRT 的官方说明，修改项目根目录中的 *.config 文件以自定义构建内容。例如：
	•	添加或删除需要的包。
	•	调整内核模块支持。
	•	配置网络、存储等功能。

3. 触发构建

推送更改到仓库后，GitHub Actions 将自动触发构建过程并生成固件。

注意事项
	•	配置文件 (*.config) 的修改需要遵循 OpenWRT 或 ImmortalWRT 的配置格式，确保兼容性。
	•	在构建前，请确认 build-openwrt.yml 文件中的分支和配置文件路径正确无误。
	•	每次构建的日志和生成的固件可以在 GitHub Actions 的工作流页面中找到。

参考资料  
	•	[OpenWRT 构建文档](https://openwrt.org/docs/guide-developer/toolchain/use-buildsystem)  
	•	[ImmortalWRT 官方文档](https://github.com/immortalwrt/immortalwrt/blob/master/README.md) 
