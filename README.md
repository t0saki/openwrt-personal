# OpenWrt Personal Build

用 GitHub Actions 从源码构建个人用 [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) 固件。成品在 [Releases](../../releases) 下载，请遵循当地法律法规使用。

当前上游：`v25.12.2`（kernel 6.12，包管理器为 **apk**，不再是 opkg）。

## Profiles

| profile | 设备 | 说明 |
|---|---|---|
| `base` | x86_64 | 通用 x86 软路由，rootfs 2 GiB，带 Intel/MT7921/MT7922 WiFi 与 USB 蓝牙驱动 |
| `alderlake` | x86_64 | `base` + `-O2 -march=alderlake`（只影响 C/C++ 用户态；PVE 虚拟机的 CPU 类型必须设为 `host`） |
| `base_docker` | x86_64 | `base` + Docker（`luci-app-dockerman`），用来跑 Nginx Proxy Manager |
| `alderlake_docker` | x86_64 | `alderlake` + Docker |
| `tr3000_v1` | Cudy TR3000 v1 | 112M 大分区布局，**必须先刷对应的大分区 U-Boot** |
| `tr3000_v1_airplay2` | Cudy TR3000 v1 | `tr3000_v1` + AirPlay 2（shairport-sync），默认不构建，可手动触发 |

所有 profile 都内置 Tailscale（`luci-app-tailscale-community`）和 EasyTier（`luci-app-easytier`，不带 web console）。默认 LAN 地址 `192.168.10.10`。

x86 profile 都带认证网关（Authelia + nginx + acme.sh），`*_docker` 另带 Docker。这些**默认全部关闭**，不手动开启就不改变路由器行为，见下文[认证网关](#认证网关authelia--nginx--npm)。

## 目录结构

```
build.env          上游版本、LAN IP、默认关闭的服务、第三方包（均 pin 到 commit）——版本只在这里改（packages/ 里的预编译包除外）
profiles/<name>    一个 profile 由哪些 config 片段组成，按顺序拼接
configs/*.config   config 片段：common / x86_64 / alderlake / authgw / docker / tr3000_v1 / airplay2
packages/<pkg>     本仓库自带的 OpenWrt 包，prepare 时拷到 package/tosaki/：
                   authelia（官方预编译二进制，版本和 hash 在它自己的 Makefile 里）、
                   authgw-nginx、dockerd-router（默认关闭用的配置）
patches/*.patch    对 ImmortalWrt 源码树的补丁（TR3000 112M UBI、dockerd init 与固定 gid、DISABLED_SERVICES）
files/             打进所有固件的 rootfs overlay（uci-defaults 等）
scripts/build.sh   本地和 CI 共用的构建脚本
```

config 片段只写**想要的东西**，依赖库、`luci-i18n-*-zh-cn` 之类交给 `make defconfig` 解析。`build.sh config` 会检查片段里每一行在最终 `.config` 里都还在，被 defconfig 静默丢掉（包改名、clone 失败、依赖缺失）时直接报错，不会把缺包的固件发出去。

## 构建

**CI**：push 到 `main`（只在构建相关文件变动时）会构建默认的五个 profile（除 `tr3000_v1_airplay2` 外全部）并发布 Release。Actions → *Build ImmortalWrt* → *Run workflow* 可以手动指定 profile 列表，例如 `["tr3000_v1_airplay2"]`。Release 只从 `main` 发布；其它分支的手动构建只留 7 天的 workflow artifact。某个 profile 失败不影响其它 profile 发布，状态会写进 release notes，失败日志在 artifact `logs-<profile>` 里；只有五个默认 profile 全部成功的构建才会标记为 Latest。x86 profile 在 collect 之后还有一步 smoke test（`build.sh smoke`，需要 sudo 和 squashfs-tools）：解开 rootfs 镜像，在 chroot 里跑 `authelia --version`、`nginx -V`（检查 auth_request/realip/geo）、`dockerd --version`，并确认 `DISABLED_SERVICES` 在 rom 里没有启动链接；不通过的 profile 不发布。

**本地**（x86_64 Linux，依赖同 [OpenWrt 构建文档](https://openwrt.org/docs/guide-developer/toolchain/install-buildsystem)）：

```sh
scripts/build.sh all tr3000_v1          # 等价于 prepare / config / download / compile / collect
ls out/tr3000_v1/
```

## 自定义

- 加减软件包：编辑 `configs/` 里对应片段；新机型新建一个片段，再在 `profiles/` 里组合。
- 升级上游：改 `build.env` 的 `IMMORTALWRT_REF`。
- 第三方包：在 `build.env` 的 `THIRD_PARTY` 里加一行 `<目录> <git url> <commit>`；如果和 feed 里的包同名，把 feed 目录加进 `OVERRIDE_FEED_DIRS`。
- 升级 Authelia：改 `packages/authelia/Makefile` 的 `PKG_VERSION` 和 `PKG_HASH`（release 里 tarball 的 sha256），先看 release notes。
- 新加会开机自启、但应该默认关闭的服务：把 init 脚本名加进 `build.env` 的 `DISABLED_SERVICES`。

## 认证网关（Authelia + nginx / NPM）

目标：LAN 设备直连被反代的服务，公网访问必须先过 Authelia（passkey/WebAuthn 优先，TOTP 兜底）。x86 profile 内置：

- **Authelia** 4.39：官方 linux-amd64-musl 二进制（`packages/authelia`），只监听 `127.0.0.1:9091`，以 `authelia` 用户运行。
- **nginx-full**：带 `auth_request`、`realip`、`geo`；基础配置在 `packages/authgw-nginx`。
- **acme.sh + luci-app-acme**：带 DNS API（Cloudflare 是 `dns_cf`），走 DNS-01，不需要开 80 端口。
- `*_docker` 另有 Docker + dockerman，用来跑 Nginx Proxy Manager（NPM 没法原生跑）。

示例配置都在 `/usr/share/authelia/`：`configuration.yml`、`users_database.yml`，以及 `nginx/` 下的 `http.conf`（谁可以跳过认证）、`protect.conf`（server 级 `auth_request`）、`portal.conf`（门户 host）、`site.conf`（原生 nginx 的完整示例）。同一套片段原生 nginx 和 NPM 都能用。

### 默认关闭，开启后跨升级保留

新刷、或从没有这些组件的旧固件升级上来，路由器的网络行为和不带它们时一样：

| 组件 | 出厂状态 |
|---|---|
| nginx | rom 里没有 rc.d 启动链接（`build.env` 的 `DISABLED_SERVICES` + `patches/0003-*`）。首次开机删掉 nginx-ssl-util 出厂的 `_lan`（443 + 自签证书 + crontab）和 `_redirect2ssl`（:80），改用没有任何 `server{}` 的 `/etc/nginx/nginx.conf`，就算手动启动也不监听端口。只在 `/etc/config/nginx` 和 `/etc/nginx/conf.d/` 都和 `/rom` 一致时才这么做；升级时恢复出来的 nginx 配置（之前就在用 nginx）原样保留。uhttpd/LuCI 不动 |
| Authelia | rc.d 里是 enable 的，但 `/etc/config/authelia` 是 `enabled '0'`，init 什么都不做 |
| dockerd（`*_docker`） | 同 nginx，没有 rc.d 链接。开机不再 `uciadd`（不往 network/firewall 写 docker 接口和 zone，不 reload fw4，`patches/0002-*`）；`/etc/docker/daemon.json` 是 `"bridge": "none"`，iptables/ip6tables/ip-forward 全关；`/etc/sysctl.d/13-br-netfilter-off.conf` 把 dockerd 包打开的 `bridge-nf-call-ip(6)tables` 关回去（`packages/dockerd-router`） |
| acme | 示例证书都是 `enabled 0`，只在 crontab 加一行每晚 `acme renew`，不会签任何东西 |

开启就是普通的 `/etc/init.d/<svc> enable` 或 `uci set`。**保留配置的 sysupgrade 会把开关和配置一起带过去**：

- nginx/dockerd 的启用状态：`build.sh prepare` 按 `DISABLED_SERVICES` 生成 `/lib/upgrade/keep.d/optin-services`，备份 enable 后才有的 `/etc/rc.d/S??<svc>` 链接（sysupgrade 自己只会带过去「已禁用」）。备份清单按**正在运行的**固件的 keep.d 生成，所以从没有这个文件的固件（本仓库 main 之前的版本、24.10 等）第一次升级上来时，已经 enable 的 nginx/dockerd 会变成关闭，见[升级须知](#升级须知)。
- 配置：`/etc/authelia/`（含 secrets 和数据库）、`/etc/nginx/`、`/etc/docker/`、`/etc/acme`、`/etc/ssl/acme`，以及 `/etc/config/` 下的 authelia/nginx/acme/dockerd/uhttpd/firewall。
- `/mnt` 盘上的东西（docker data-root、NPM 数据、挪到 /mnt 的 Authelia 数据库）不进备份，刷机也不碰它。
- `sysupgrade -n` 或全新刷机：全部回到默认关闭。

### 启用 Authelia

```sh
mkdir -p /etc/authelia
cp /usr/share/authelia/configuration.yml /usr/share/authelia/users_database.yml /etc/authelia/
vi /etc/authelia/configuration.yml   # home.example.com / auth.home.example.com 换成自己的域名
# 交互输入密码，输出 "Digest: $argon2id$..."；不会留在 shell 历史和进程列表里
authelia crypto hash generate argon2 --config /etc/authelia/configuration.yml
vi /etc/authelia/users_database.yml  # REPLACE_ME 改成不好猜的用户名（别用 admin），粘贴 Digest，disabled 改成 false
uci set authelia.main.enabled=1 && uci commit authelia
/etc/init.d/authelia check && /etc/init.d/authelia restart
logread -e authelia
```

- 首次启动在 `/etc/authelia/secrets/` 生成 storage/session/jwt 三个随机密钥（root:authelia 0640），以 `AUTHELIA_*_FILE` 传给 Authelia，配置文件里没有任何 secret。**`secrets/storage` 不能丢、也不能重新生成**：数据库里的 passkey/TOTP 用它加密，init 发现数据库还在而密钥没了会拒绝启动。
- 属主：`/etc/authelia` 和 `secrets/` 是 root:authelia 0750，Authelia 只能读；它唯一能写的是数据库所在目录（authelia 0700）。init 以 root 改属主时一律 `chown -h`（busybox 不加 `-h` 会跟随 symlink），被攻破的 Authelia 没法借此提权。
- `authelia` 用户的 uid/gid 固定为 9091（`docker` 组固定为 2375，`patches/0002-*`）。init 启动前检查用户存在且 id 没被别的账户占用，否则拒绝启动（procd 遇到不存在的用户会悄悄以 root 运行）。从旧固件保留配置升级后可以自查：`awk -F: '{print $3}' /etc/passwd | sort | uniq -d`，`/etc/group` 同理，输出应为空。
- 注册 passkey/TOTP 时要的一次性验证码写在 `/tmp/authelia/notification.txt`（没配 SMTP）。
- 数据库默认是 `/etc/authelia/db/db.sqlite3`，跟着配置备份。想放到 /mnt：先在盘上建一个**专用目录**，再 `uci set authelia.main.storage=/mnt/<disk>/authelia/db.sqlite3`。该目录会整个交给 authelia。目录不存在、不在已挂载的盘上（盘没挂上时挂载点只是 overlay 上的空目录），或者就是挂载点本身时，Authelia 都不启动，不会在 overlay 上悄悄建一个空库。放在 /mnt 时要自己把它和 `secrets/` 一起备份。
- cookie 域（`session.cookies[].domain`）用专门的子域，比如 `home.example.com`，不要用主域：cookie 会发给该域下所有子域，其中任何一个托管在别处的服务（VPS、CF Worker、第三方）拿到它都能重放网关会话。两台路由器各用自己的子域（`home-zj`、`home-sg`……），登录态也就互不覆盖。
- passkey 绑定门户主机名（`authelia_url`），改了它已注册的 passkey 全部失效。
- 内存：空闲约 100 MB，每个并发的密码登录（argon2）再加 64 MB，passkey 登录不用；`uci authelia.main.memlimit` 是 Go 的软上限，挡不住并发。Authelia 对密码登录没有 rate limit，所以 `portal.conf` 给 `/api/firstfactor*` 加了全局最多 4 个并发、每个来源地址 10 次/分钟（突发 5）的限制，超出返回 429。

### LAN 直连、公网认证是怎么做的

判定在 nginx 里做，Authelia 只负责认证（`configuration.yml` 里故意没有 `networks` 规则）：

- `http.conf`：`geo $realip_remote_addr` 判断来源是不是 LAN（LAN 网段 → 1，**路由器自己的 IP → 0**），`map $host` 列出不需要认证的公开 host（门户本身必须在里面），合成 `$authelia_skip`。用 TCP 层的源地址 `$realip_remote_addr` 而不是 `$remote_addr`：NPM 对所有 RFC1918 来源都信任 `X-Real-IP`，后者可以伪造。
- `protect.conf`：server 级 `auth_request`，内部 auth location 里 `if ($authelia_skip) { return 200; }` 直接短路。LAN 请求根本不会到 Authelia，Authelia 停了 LAN 照常用；公网请求在 Authelia 不可用时得到 500（fail closed）。
- `portal.conf`：门户 host 自己写 `location /`，把 `X-Forwarded-For` 设成真实来源，防止客户端伪造 XFF 躲过 Authelia 的防爆破。

LAN 设备要真的「直连」，服务域名得在 LAN 里解析到路由器的 LAN IP（split DNS）。坑：

- **OpenClash fake-ip**：LAN 设备拿到 198.18.x，流量进 TUN 后由路由器自己重新拨出，源地址变成路由器，于是被要求认证。在 OpenClash「覆写设置 → DNS → Hosts」里写 `svc.home.example.com` → 路由器 LAN IP（hosts 优先于 fake-ip），**只写 A 记录**，AAAA 自然返回空。写具体子域或专门的子域后缀，别写 `+.example.com` 把指向 VPS 的子域也劫持了。OpenClash 接管 DNS 时 dnsmasq 的 `address=` 不生效。
- **不要把路由器 IP 或 127.0.0.1 放进 LAN 集合**：frpc、mihomo、Tailscale/WireGuard 的 masquerade、hairpin NAT、docker-proxy 进来的连接都显示成它们，放进去等于把公网也放行了。
- **LAN 里所有会把外面的流量转进来的主机同理**，都要像路由器一样写成 `<ip> 0;`：跑 frpc/socks5/ssh 隧道的机器（比如经 frps 暴露 socks5 的 LXC）、Tailscale subnet router/exit node、cloudflared、对端口转发做 SNAT 的上游网关。公网经它们连进来，源地址就是它们的 LAN IP。更稳的做法是只把真正的客户端网段（比如 DHCP 地址池）设为 1，而不是整个 /24。
- **IPv6**：LAN 设备的 GUA 前缀是运营商动态下发的，不在 LAN 集合里，走 v6 就会被要求认证，所以 split DNS 只给 A。不要把 PD 前缀写进 geo（前缀一变就可能放行别人）；真要 v6 直连，用固定 ULA（`network.globals.ula_prefix`）并把它加进 geo，同时把路由器自己的 ULA 地址写成 0（`http.conf` 里有示例）。
- 同网段的 IoT/访客设备一样会被放行：LAN 本身不是安全边界，需要的话拆网段。
- LAN 请求不经过 Authelia，也就没有 `Remote-User` 头，而且客户端可以自己带这个头：任何后端都不能信任 `Remote-User`/`Remote-Groups` 做登录。
- 只保护 HTTP(S) 反代；NPM 的 Streams（TCP/UDP 转发）不受保护。
- 回跳地址用 `$host` 拼，不带端口；服务不在 443 上时把 `protect.conf` 抄一份改成 `$http_host`。

### 方案一：原生 nginx（所有 x86 profile）

uhttpd 继续占 :80（LuCI），nginx 只监听 443。

1. 先签证书（证书文件不存在时 `nginx -t` 失败，nginx 起不来）。LuCI → 服务 → ACME，或者：
   ```sh
   uci set acme.@acme[0].account_email='you@example.com'
   uci batch <<'EOT'
   set acme.example=cert
   set acme.example.enabled='1'
   set acme.example.staging='0'
   set acme.example.validation_method='dns'
   set acme.example.dns='dns_cf'
   add_list acme.example.domains='home.example.com'
   add_list acme.example.domains='*.home.example.com'
   set acme.example.key_type='ec256'
   add_list acme.example.credentials='CF_Token="<有 Zone.DNS 编辑权限的 token>"'
   add_list acme.example.credentials='CF_Zone_ID="<zone id>"'
   commit acme
   EOT
   /etc/init.d/acme renew && logread -f -e acme
   ```
   不带通配的那个放第一个，它决定文件名：`/etc/ssl/acme/home.example.com.fullchain.crt` 和 `home.example.com.key`。之后续期成功会自动 reload nginx。
2. 配置（`protect.conf`/`portal.conf` 用绝对路径 include，跟着固件更新；`/etc/nginx/` 下的文件跟着配置备份）：
   ```sh
   cp /usr/share/authelia/nginx/http.conf /etc/nginx/conf.d/authelia-http.conf  # 改 LAN 网段、路由器 IP、公开 host
   cp /usr/share/authelia/nginx/site.conf /etc/nginx/conf.d/gateway.conf      # 改域名、证书、后端
   nginx -t -c /etc/nginx/nginx.conf
   ```
3. 确认 443 没被占（lucky、frps 等）再开：
   ```sh
   netstat -lntp | grep ':443 '
   /etc/init.d/nginx enable && /etc/init.d/nginx start
   ```
4. 最后才开放 WAN 443（先有认证、再开口子）：
   ```sh
   uci batch <<'EOT'
   set firewall.authgw=rule
   set firewall.authgw.name='Allow-WAN-HTTPS'
   set firewall.authgw.src='wan'
   set firewall.authgw.proto='tcp'
   set firewall.authgw.dest_port='443'
   set firewall.authgw.target='ACCEPT'
   set firewall.authgw.family='any'
   commit firewall
   EOT
   /etc/init.d/firewall reload
   nft list ruleset | grep -c openclash   # OpenClash 注册了 firewall include，reload 后会自己挂回去
   ```

### 方案二：NPM（`*_docker` profile）

和原生 nginx 二选一（都要 443）。

1. 启用 Docker。先把 `/etc/docker/daemon.json` 的 `data-root` 改成 /mnt 盘上的目录（例如 `/mnt/sda1/docker`）：data-root 落在 overlay/tmpfs 上（比如盘没挂上）时 dockerd 拒绝启动。
   ```sh
   vi /etc/docker/daemon.json
   /etc/init.d/dockerd enable && /etc/init.d/dockerd start
   docker info | grep -E 'Docker Root Dir|Storage Driver'
   ```
   UCI 里的 `alt_config_file` 指向这个文件，所以 LuCI Docker 配置页的 data_root、镜像加速等选项不生效，改 daemon.json。没有 docker0 和 iptables，容器只用 `network_mode: host`。
2. uhttpd 让出 80，LuCI 改走 `http://<LAN IP>:8080`：
   ```sh
   uci -q delete uhttpd.main.listen_http; uci -q delete uhttpd.main.listen_https
   uci add_list uhttpd.main.listen_http='0.0.0.0:8080'
   uci add_list uhttpd.main.listen_http='[::]:8080'
   uci set uhttpd.main.redirect_https='0'
   uci commit uhttpd && /etc/init.d/uhttpd restart
   ```
   用通配地址，不要绑 LAN IP：开机时 br-lan 可能还没地址，绑定失败就进不去 LuCI。
3. 先把 NPM 的管理口锁到一台管理机。NPM 2.16 首次启动不建默认账号，**谁先打开 setup 向导谁就是管理员**；host 网络下管理界面 :81 和 API :3000 监听所有地址，fw4 默认只挡 WAN，LAN、input ACCEPT 的 VPN zone（Tailscale、EasyTier、OpenVPN）以及经 LAN 里中转主机进来的公网流量都能访问。NPM 管理员可以给任意 host 写 `auth_request off;` 绕过网关，还能拿走所有证书私钥。`src '*'` 的规则排在各 zone 之前，本机（lo）不受影响：
   ```sh
   uci batch <<'EOT'
   set firewall.npm_admin_ok=rule
   set firewall.npm_admin_ok.name='Allow-NPM-admin'
   set firewall.npm_admin_ok.src='*'
   set firewall.npm_admin_ok.src_ip='<管理机 IP>'
   set firewall.npm_admin_ok.proto='tcp'
   set firewall.npm_admin_ok.dest_port='81 3000'
   set firewall.npm_admin_ok.target='ACCEPT'
   set firewall.npm_admin=rule
   set firewall.npm_admin.name='Reject-NPM-admin'
   set firewall.npm_admin.src='*'
   set firewall.npm_admin.proto='tcp'
   set firewall.npm_admin.dest_port='81 3000'
   set firewall.npm_admin.target='REJECT'
   set firewall.npm_admin.family='any'
   commit firewall
   EOT
   /etc/init.d/firewall reload
   ```
4. 起 NPM（示例 compose：`/usr/share/dockerd-router/npm/docker-compose.yml`，host 网络，能直接访问 `127.0.0.1:9091`，看到的是真实客户端地址），**起来后马上**在管理机上打开 `http://<LAN IP>:81` 完成 setup：
   ```sh
   mkdir -p /mnt/sda1/npm/data/nginx/custom && cd /mnt/sda1/npm
   cp /usr/share/dockerd-router/npm/docker-compose.yml .
   cp /usr/share/authelia/nginx/http.conf data/nginx/custom/http.conf        # 改 LAN 网段、路由器 IP、公开 host
   cp /usr/share/authelia/nginx/protect.conf data/nginx/custom/server_proxy.conf
   docker compose up -d
   ```
   - NPM 把 `server_proxy.conf` include 进每个 proxy host，新建的 host 默认就受保护；不需要认证的 host 写进 `http.conf` 的白名单。各 host Advanced 里旧的 Authelia 片段要先删掉（重复的 `auth_request` 会让 nginx -t 失败）。
   - 门户 host `auth.home.example.com` → `127.0.0.1:9091`，打开 Force SSL，把 `portal.conf` 的内容贴进 Advanced。
   - forward host 写 IP，不写主机名：容器走路由器的 DNS，会拿到 fake-ip。
   - 不要用 `INITIAL_ADMIN_PASSWORD` 预置管理员：密码会落进 compose 文件和 NPM 日志。
5. setup 完成后才开放 WAN：同方案一的防火墙规则，`dest_port` 改成 `'80 443'`。

### 升级须知

- `/etc/nginx/`、`/etc/docker/`、`/etc/authelia/` 是整目录保留：保留配置升级后用的还是旧文件，新固件对这些默认文件的改动不会覆盖进来；`/usr/share/authelia/` 下的示例和片段跟着固件更新。
- 不要在路由器上 `apk add`/`apk upgrade` dockerd：它的 postinst 会 enable + `uciadd` + start（改 network/firewall、reload fw4）。只随固件升级。
- **从没有 `keep.d/optin-services` 的固件第一次升级**（本仓库 main 之前的版本、24.10 等）：备份清单由旧固件决定，`/etc/rc.d/S??nginx`、`S??dockerd` 不在里面，新 rom 里也没有，升级后已在用的 nginx/dockerd 是关闭的（配置都在）。三选一：升级前在旧固件上 `printf '/etc/rc.d/S??nginx\n/etc/rc.d/S??dockerd\n' >> /etc/sysupgrade.conf`；或者这次用 `sysupgrade -c`（备份 overlay 里 /etc 下所有改动过的文件，rc.d 链接也在内）；或者升级后 `/etc/init.d/nginx enable && /etc/init.d/nginx start`。之后的升级不用再管。
- 升级时恢复出来的 `/etc/config/nginx`（之前就用 UCI 的 `_lan` 等 server、`conf.d/*.locations`）不会被首次开机脚本改动；它只处理和 `/rom` 完全一致的出厂配置。
- 升级 Authelia 前看 release notes：示例里的 `experimental_enable_passkey_uv_two_factors` 以后会被替换掉，届时旧配置会启动失败。

## 注意

- 固件内核是自己编译的，vermagic 和官方不同，**刷机后不能从官方源 `apk add kmod-*`**；需要的内核模块请直接编进固件。每次构建的 packages/kmods 会作为 workflow artifact 保留 7 天，但只能装在同一次构建的固件上。`*_docker` 比同目标不带 docker 的固件多几个 kmod，vermagic 也不同，两者的 kmod 不能混用。
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
