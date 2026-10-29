# OpenWrt Personal Build

用 GitHub Actions 从源码构建个人用 [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) 固件。成品在 [Releases](../../releases) 下载，请遵循当地法律法规使用。

当前上游：`v25.12.2`（kernel 6.12，包管理器为 **apk**，不再是 opkg）。

## Profiles

| profile | 设备 | 说明 |
|---|---|---|
| `base` | x86_64 | 通用 x86 软路由，rootfs 2 GiB，带 Intel/MT7921/MT7922 WiFi 与 USB 蓝牙驱动 |
| `alderlake` | x86_64 | `base` + `-O2 -march=alderlake`（只影响 C/C++ 用户态；PVE 虚拟机的 CPU 类型必须设为 `host`） |
| `tr3000_v1` | Cudy TR3000 v1 | 112M 大分区布局，**必须先刷对应的大分区 U-Boot** |
| `tr3000_v1_airplay2` | Cudy TR3000 v1 | `tr3000_v1` + AirPlay 2（shairport-sync），默认不构建，可手动触发 |

所有 profile 都内置 Tailscale（`luci-app-tailscale-community`）和 EasyTier（`luci-app-easytier`，不带 web console）。默认 LAN 地址 `192.168.10.10`。

## 目录结构

```
build.env          上游版本、LAN IP、第三方包（均 pin 到 commit）——版本只在这里改
profiles/<name>    一个 profile 由哪些 config 片段组成，按顺序拼接
configs/*.config   config 片段：common / x86_64 / alderlake / tr3000_v1 / airplay2
patches/*.patch    对 ImmortalWrt 源码树的补丁（TR3000 112M UBI）
files/             打进固件的 rootfs overlay（uci-defaults 等）
scripts/build.sh   本地和 CI 共用的构建脚本
```

config 片段只写**想要的东西**，依赖库、`luci-i18n-*-zh-cn` 之类交给 `make defconfig` 解析。`build.sh config` 会检查片段里每一行在最终 `.config` 里都还在，被 defconfig 静默丢掉（包改名、clone 失败、依赖缺失）时直接报错，不会把缺包的固件发出去。

## 构建

**CI**：push 到 `main`（只在构建相关文件变动时）会构建默认的三个 profile 并发布 Release。Actions → *Build ImmortalWrt* → *Run workflow* 可以手动指定 profile 列表，例如 `["tr3000_v1_airplay2"]`。Release 只从 `main` 发布；其它分支的手动构建只留 7 天的 workflow artifact。某个 profile 失败不影响其它 profile 发布，状态会写进 release notes，失败日志在 artifact `logs-<profile>` 里；只有三个默认 profile 全部成功的构建才会标记为 Latest。

**本地**（x86_64 Linux，依赖同 [OpenWrt 构建文档](https://openwrt.org/docs/guide-developer/toolchain/install-buildsystem)）：

```sh
scripts/build.sh all tr3000_v1          # 等价于 prepare / config / download / compile / collect
ls out/tr3000_v1/
```

## 自定义

- 加减软件包：编辑 `configs/` 里对应片段；新机型新建一个片段，再在 `profiles/` 里组合。
- 升级上游：改 `build.env` 的 `IMMORTALWRT_REF`。
- 第三方包：在 `build.env` 的 `THIRD_PARTY` 里加一行 `<目录> <git url> <commit>`；如果和 feed 里的包同名，把 feed 目录加进 `OVERRIDE_FEED_DIRS`。

## 注意

- 固件内核是自己编译的，vermagic 和官方不同，**刷机后不能从官方源 `apk add kmod-*`**；需要的内核模块请直接编进固件。每次构建的 packages/kmods 会作为 workflow artifact 保留 7 天，但只能装在同一次构建的固件上。
- 25.12 改用 apk，从 24.10 升级会丢失用户自行安装的包。
- TR3000 的 sysupgrade 镜像超过 112M 时上游 `check-size` 会删掉镜像，`build.sh collect` 发现没有可刷写镜像就让该 profile 失败，不会发出空 release。

## 从旧固件（`build-2026*` 及更早）升级

- passwall 去掉了 shadowsocks-rust：保留配置升级后，类型为 SS-Rust 的节点需要改成 Xray 或 sing-box 类型。
- TR3000 去掉了 frps 和 ngrokc。
- 旧固件往 `/etc/sysctl.conf` 追加过 `default_qdisc=fq` 和 `bbr` 两行：前者因为内核没有 `sch_fq` 本来就不生效，后者已由 `kmod-tcp-bbr` 自带的 `/etc/sysctl.d/12-tcp-bbr.conf` 提供。保留配置升级时这两行会留着，可以手动删掉。

## 参考

- [OpenWrt build system](https://openwrt.org/docs/guide-developer/toolchain/use-buildsystem)
- [ImmortalWrt](https://github.com/immortalwrt/immortalwrt)
- [EasyTier/luci-app-easytier](https://github.com/EasyTier/luci-app-easytier)
