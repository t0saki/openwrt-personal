#!/usr/bin/env bash
# Build ImmortalWrt for one profile, locally or in CI.
#
#   scripts/build.sh prepare             clone source, feeds, third-party pkgs, patches
#   scripts/build.sh config  <profile>   compose configs/*.config -> .config, validate
#   scripts/build.sh download
#   scripts/build.sh compile
#   scripts/build.sh collect <profile>   copy images to $OUT_DIR/<profile>/
#   scripts/build.sh smoke   <profile>   run collected x86_64 rootfs binaries (sudo)
#   scripts/build.sh all     <profile>
#
# Env: SRC_DIR (default ./immortalwrt), OUT_DIR (default ./out),
#      GO_BOOTSTRAP_ROOT (optional GOROOT >= 1.24 used to bootstrap host Go),
#      BUILD_ID (image name suffix, default tosaki-YYYYMMDD).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../build.env
. "$ROOT/build.env"
SRC_DIR="${SRC_DIR:-$ROOT/immortalwrt}"
OUT_DIR="${OUT_DIR:-$ROOT/out}"
BUILD_ID="${BUILD_ID:-tosaki-$(date +%Y%m%d)}"

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

profile_fragments() {
	local profile="$1" f
	[ -f "$ROOT/profiles/$profile" ] || die "unknown profile '$profile' (see profiles/)"
	while read -r f; do
		[ -n "$f" ] || continue
		[ -f "$ROOT/configs/$f.config" ] || die "profile $profile: missing configs/$f.config"
		echo "$ROOT/configs/$f.config"
	done < "$ROOT/profiles/$profile"
}

prepare() {
	if [ ! -d "$SRC_DIR/.git" ]; then
		log "clone $IMMORTALWRT_REPO@$IMMORTALWRT_REF"
		# Full history (blob-less) is needed: scripts/getver.sh counts commits.
		git clone -b "$IMMORTALWRT_REF" --single-branch --filter=blob:none \
			"$IMMORTALWRT_REPO" "$SRC_DIR"
		cd "$SRC_DIR"
	else
		# Re-running on an existing tree: move to the pinned ref and drop
		# earlier fixups/patches so they apply to pristine sources again.
		cd "$SRC_DIR"
		log "reset tree to $IMMORTALWRT_REF"
		git fetch -q --filter=blob:none origin "$IMMORTALWRT_REF"
		git checkout -qf FETCH_HEAD
	fi

	log "feeds update"
	# Pinned feeds are not updated in place, so feed edits from an earlier run
	# (fixups, deleted overrides, feed patches) would stick and patches would
	# no longer apply. Reset them to their pinned commit first.
	local f
	for f in feeds/*/.git; do
		[ -e "$f" ] || continue
		git -C "${f%/.git}" reset -q --hard
	done
	./scripts/feeds update -a

	log "local packages"
	rm -rf package/tosaki
	cp -a "$ROOT/packages" package/tosaki
	ls package/tosaki

	log "third-party packages"
	local d
	for d in $OVERRIDE_FEED_DIRS; do rm -rf "$d"; done
	local dir url commit
	while read -r dir url commit; do
		[ -n "$dir" ] || continue
		rm -rf "package/$dir"
		git init -q "package/$dir"
		git -C "package/$dir" fetch -q --depth 1 "$url" "$commit"
		git -C "package/$dir" checkout -q FETCH_HEAD
		echo "package/$dir <- $url@$commit"
	done <<< "$THIRD_PARTY"

	log "source fixups"
	# Default LAN address.
	sed -i "s/192\.168\.1\.1/$LAN_IP/g" package/base-files/files/bin/config_generate
	# Rust CI LLVM artifacts expire upstream; build LLVM like OpenWrt does
	# (openwrt/packages 4c3a649dd7). Only matters if something pulls rust.
	sed -i 's/--set=llvm\.download-ci-llvm=true/--set=llvm.download-ci-llvm=false/' \
		feeds/packages/lang/rust/Makefile
	# apk refuses two packages owning /etc/config/openvpn; the 'myvpn' section
	# is recreated by files/etc/uci-defaults/50-openvpn-myvpn instead.
	rm -f feeds/luci/applications/luci-app-openvpn-server/root/etc/config/openvpn

	log "feeds install"
	./scripts/feeds install -a

	log "patches"
	local p
	for p in "$ROOT"/patches/*.patch; do
		[ -e "$p" ] || continue
		git apply "$p"
		echo "applied: ${p##*/}"
	done

	log "files overlay"
	rm -rf files
	cp -a "$ROOT/files" files
	# DISABLED_SERVICES have no rc.d link in rom, and sysupgrade only carries
	# "disabled" over by itself. Keep the link a user created by enabling one;
	# sysupgrade expands these globs, non-matching ones are ignored.
	local svc
	mkdir -p files/lib/upgrade/keep.d
	for svc in $DISABLED_SERVICES; do
		printf '/etc/rc.d/S??%s\n/etc/rc.d/K??%s\n' "$svc" "$svc"
	done > files/lib/upgrade/keep.d/optin-services
}

# The filogic target pulls bridger, which needs a BPF toolchain. Use the
# release's prebuilt llvm-bpf instead of compiling LLVM (same version).
fetch_prebuilt_llvm_bpf() {
	[ "$(uname -m)" = x86_64 ] || return 0
	[ -f llvm-bpf/.llvm-version ] && return 0
	local board subtarget base name
	board="$(sed -n 's/^CONFIG_TARGET_BOARD="\(.*\)"/\1/p' .config)"
	subtarget="$(sed -n 's/^CONFIG_TARGET_SUBTARGET="\(.*\)"/\1/p' .config)"
	base="https://downloads.immortalwrt.org/releases/${IMMORTALWRT_REF#v}/targets/$board/$subtarget"
	name="$(curl -fsSL "$base/sha256sums" | sed -n 's/^\([0-9a-f]*\) \*\(llvm-bpf-.*\.tar\.zst\)$/\1 \2/p')" || name=
	if [ -z "$name" ]; then
		echo "::warning::no prebuilt llvm-bpf at $base, LLVM will be built from source (+1-2h)"
		return 0
	fi
	log "prebuilt ${name#* }"
	curl -fsSL -o "${name#* }" "$base/${name#* }"
	echo "${name% *}  ${name#* }" | sha256sum -c -
	tar --zstd -xf "${name#* }"
	rm -f "${name#* }"
}

config() {
	local profile="$1" seed frags
	# Assigned separately so a die() inside the substitution aborts the script.
	frags="$(profile_fragments "$profile")"
	[ -n "$frags" ] || die "profile $profile lists no fragments"
	cd "$SRC_DIR"
	seed="$(mktemp)"
	# shellcheck disable=SC2086
	cat $frags > "$seed"
	if [ -n "${GO_BOOTSTRAP_ROOT:-}" ]; then
		printf 'CONFIG_GOLANG_EXTERNAL_BOOTSTRAP_ROOT="%s"\n# CONFIG_GOLANG_BUILD_BOOTSTRAP is not set\n' \
			"$GO_BOOTSTRAP_ROOT" >> "$seed"
	fi

	log "config $profile: $(paste -sd' ' "$ROOT/profiles/$profile")"
	cp "$seed" .config
	make defconfig >/dev/null
	if grep -q '^CONFIG_USE_LLVM_BUILD=y' .config; then
		fetch_prebuilt_llvm_bpf
		cp "$seed" .config
		make defconfig >/dev/null
	fi

	# defconfig silently drops symbols it can't satisfy (renamed package,
	# failed clone, missing dependency). Fail instead of shipping without them.
	local line sym missing=0
	while read -r line; do
		case "$line" in
		CONFIG_*=*)
			grep -qxF "$line" .config || { echo "dropped: $line"; missing=1; } ;;
		"# CONFIG_"*" is not set")
			sym="${line#\# }"; sym="${sym%% *}"
			! grep -q "^$sym=" .config || { echo "still set: $(grep "^$sym=" .config)"; missing=1; } ;;
		esac
	done < "$seed"
	rm -f "$seed"
	[ "$missing" = 0 ] || die "config $profile does not resolve as written"

	./scripts/diffconfig.sh > "diffconfig.$profile"
	grep -E '^CONFIG_(TARGET_PROFILE|USE_LLVM_[A-Z]+)=' .config || true
}

download() {
	cd "$SRC_DIR"
	log "download"
	make download -j"$(nproc)" || make download -j1 V=s
}

compile() {
	cd "$SRC_DIR"
	log "compile with $(nproc) jobs, EXTRA_IMAGE_NAME=$BUILD_ID"
	rm -rf bin/targets
	if ! make -j"$(nproc)" BUILD_LOG=1 EXTRA_IMAGE_NAME="$BUILD_ID" \
		DISABLED_SERVICES="$DISABLED_SERVICES"; then
		# Show the logs of whatever failed instead of re-running serially.
		# error.txt lines look like "   ERROR: package/feeds/x/y failed to build."
		local dir
		cat logs/error.txt logs/*/error.txt 2>/dev/null |
			sed -n 's/^ *ERROR: \([^ ]*\) .*/\1/p' | sort -u |
			while read -r dir; do
				echo "::group::$dir"
				find "logs/$dir" -maxdepth 2 -name '*.txt' -exec tail -n 80 {} + || true
				echo "::endgroup::"
			done || true
		die "compile failed"
	fi
}

collect() {
	local profile="$1" board tdir device dest f name base ext svc links
	cd "$SRC_DIR"
	board="$(sed -n 's/^CONFIG_TARGET_BOARD="\(.*\)"/\1/p' .config)"
	# The rootfs the images were made from must not start opt-in services.
	for svc in $DISABLED_SERVICES; do
		links="$(find build_dir/target-*/root-"$board"/etc/rc.d -name "[SK][0-9][0-9]$svc" 2>/dev/null || true)"
		[ -z "$links" ] || die "rootfs enables $svc despite DISABLED_SERVICES: $links"
	done
	tdir="bin/targets/$board"
	tdir="$tdir/$(sed -n 's/^CONFIG_TARGET_SUBTARGET="\(.*\)"/\1/p' .config)"
	device="$(sed -n 's/^CONFIG_TARGET_PROFILE="DEVICE_\(.*\)"/\1/p' .config)"
	# check-size only warns and deletes an oversized image, make still succeeds.
	compgen -G "$tdir/*$BUILD_ID*$device*-sysupgrade.bin" >/dev/null ||
		compgen -G "$tdir/*$BUILD_ID*$device*-combined*.img.gz" >/dev/null ||
		die "no flashable image for $device in $tdir (too big for check-size?)"
	dest="$OUT_DIR/$profile"
	rm -rf "$dest"; mkdir -p "$dest"
	log "collect $profile ($device) -> $dest"
	for f in "$tdir"/*; do
		[ -f "$f" ] || continue
		name="${f##*/}"
		# Images for this device plus the build metadata; skips other SoCs' bl2.
		case "$name" in
		*"$BUILD_ID"*"$device"*|*"$BUILD_ID"*.manifest) ;;
		config.buildinfo|feeds.buildinfo|version.buildinfo) ;;
		*) continue ;;
		esac
		case "$name" in
		*.img.gz) ext=img.gz ;;
		*.tar.gz) ext=tar.gz ;;
		*.*) ext="${name##*.}" ;;
		esac
		base="${name%."$ext"}"
		cp "$f" "$dest/${base}_${IMMORTALWRT_REF}_${profile}.$ext"
	done
	cp "diffconfig.$profile" "$dest/diffconfig_${IMMORTALWRT_REF}_${profile}"
	ls -l "$dest"
}

# Prints the output of "$@" run inside the unpacked rootfs. A -march image
# may need instructions this CPU lacks: on SIGILL (132) warn and print
# nothing, so the caller falls back to a static check.
smoke_exec() {
	local rc=0 out
	out="$($SUDO chroot "$SMOKE_ROOT" "$@" 2>&1)" || rc=$?
	if [ "$rc" = 132 ]; then
		echo "::warning::smoke: $1 got SIGILL on this CPU (-march image), static check only" >&2
		return 0
	fi
	[ "$rc" = 0 ] || { printf '%s\n' "$out" >&2; return 1; }
	printf '%s\n' "$out"
}

# Cheap check of what actually ships: unpack the collected squashfs rootfs and
# run the new binaries in a chroot. Needs root (device nodes, chroot) and
# squashfs-tools; x86_64 images on an x86_64 host only.
smoke() {
	local profile="$1" img work svc out ver m f n
	cd "$SRC_DIR"
	if [ "$(uname -m)" != x86_64 ] || ! grep -q '^CONFIG_TARGET_x86_64=y' .config; then
		echo "smoke: needs an x86_64 image and host, skipped"
		return 0
	fi
	img="$(compgen -G "$OUT_DIR/$profile/*squashfs-rootfs*.img.gz")" ||
		die "smoke: no squashfs rootfs image in $OUT_DIR/$profile (run collect first)"
	[ "$(wc -l <<< "$img")" = 1 ] || die "smoke: several rootfs images in $OUT_DIR/$profile"
	SUDO=; [ "$(id -u)" = 0 ] || SUDO=sudo
	work="$(mktemp -d)"
	# shellcheck disable=SC2064
	trap "$SUDO rm -rf '$work'" EXIT
	SMOKE_ROOT="$work/root"

	log "smoke $profile: ${img##*/}"
	gzip -dc "$img" > "$work/rootfs.img"
	$SUDO unsquashfs -no-progress -d "$SMOKE_ROOT" "$work/rootfs.img" >/dev/null
	rm -f "$work/rootfs.img"

	for svc in $DISABLED_SERVICES; do
		! compgen -G "$SMOKE_ROOT/etc/rc.d/[SK][0-9][0-9]$svc" >/dev/null ||
			die "smoke: rom enables $svc despite DISABLED_SERVICES"
		grep -qxF "/etc/rc.d/S??$svc" "$SMOKE_ROOT/lib/upgrade/keep.d/optin-services" ||
			die "smoke: keep.d does not carry an enabled $svc across sysupgrade"
	done

	# A sysupgrade keeps the old passwd/group and only appends missing names,
	# so ids this image adds must be fixed, not dynamic (32768 up).
	for f in passwd group; do
		out="$($SUDO cut -d: -f3 "$SMOKE_ROOT/etc/$f" | sort | uniq -d)"
		[ -z "$out" ] || die "smoke: duplicate ids in rom /etc/$f: $out"
		for n in authelia docker; do
			# shellcheck disable=SC2016
			out="$($SUDO awk -F: -v n="$n" '$1 == n && $3 >= 32768' "$SMOKE_ROOT/etc/$f")"
			[ -z "$out" ] || die "smoke: $n has a dynamic id in rom /etc/$f: $out"
		done
	done

	if grep -q '^CONFIG_PACKAGE_authelia=y' .config; then
		ver="$(sed -n 's/^PKG_VERSION:=//p' "$ROOT/packages/authelia/Makefile")"
		out="$(smoke_exec /usr/bin/authelia --version)" || die "smoke: authelia --version failed"
		[ -z "$out" ] || grep -qF "v$ver" <<< "$out" || die "smoke: authelia says '$out', expected v$ver"
		$SUDO grep -qx "[[:space:]]*option enabled '0'" "$SMOKE_ROOT/etc/config/authelia" ||
			die "smoke: authelia is not off by default"
		echo "authelia: ${out:-present}"
	fi

	if grep -q '^CONFIG_PACKAGE_nginx-full=y' .config; then
		out="$(smoke_exec /usr/sbin/nginx -V)" || die "smoke: nginx -V failed"
		[ -n "$out" ] || out="$(grep -ao -- '--with[a-z0-9_-]*' "$SMOKE_ROOT/usr/sbin/nginx" || true)"
		for m in --with-http_auth_request_module --with-http_realip_module; do
			grep -qF -- "$m" <<< "$out" || die "smoke: nginx lacks $m"
		done
		! grep -qF -- --without-http_geo_module <<< "$out" || die "smoke: nginx lacks geo"
		! grep -qE '^[^#]*\blisten\b' "$SMOKE_ROOT/etc/nginx/nginx.conf" ||
			die "smoke: shipped nginx.conf listens on something"
		echo "nginx: auth_request, realip and geo present"
	fi

	if grep -q '^CONFIG_PACKAGE_dockerd=y' .config; then
		out="$(smoke_exec /usr/bin/dockerd --version)" || die "smoke: dockerd --version failed"
		[ -z "$out" ] || grep -q '^Docker version' <<< "$out" || die "smoke: dockerd says '$out'"
		grep -q check_data_root "$SMOKE_ROOT/etc/init.d/dockerd" ||
			die "smoke: dockerd init lacks patches/0002"
		[ -f "$SMOKE_ROOT/etc/sysctl.d/13-br-netfilter-off.conf" ] ||
			die "smoke: dockerd-router sysctl override missing"
		echo "dockerd: ${out:-present}"
	fi
}

cmd="${1:-}"
case "$cmd" in
prepare|download|compile) "$cmd" ;;
config|collect|smoke) [ -n "${2:-}" ] || die "usage: $0 $cmd <profile>"; "$cmd" "$2" ;;
all)
	[ -n "${2:-}" ] || die "usage: $0 all <profile>"
	prepare; config "$2"; download; compile; collect "$2" ;;
*) sed -n '2,14p' "$0"; exit 1 ;;
esac
