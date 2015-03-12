#!/usr/bin/env bash

# This mkimage-alpine.sh is a modified version from
# https://github.com/docker/docker/blob/master/contrib/mkimage-alpine.sh.
# Changes were inspired by work done by Eivind Uggedal (uggedal) and
# Luis Lavena (luislavena).

readonly ARCH="$(uname -m)"
declare REL="${REL:-edge}"
declare MIRROR="${MIRROR:-http://nl.alpinelinux.org/alpine}"
declare TIMEZONE="${TIMEZONE:-UTC}"

set -eo pipefail; [[ "$TRACE" ]] && set -x

[[ "$(id -u)" -eq 0 ]] || {
	printf >&2 '%s requires root\n' "$0" && exit 1
}

usage() {
	printf >&2 '%s: [-r release] [-m mirror] [-s] [-e] [-c] [-t]\n' "$0" && exit 1
}

output_redirect() {
	if [[ "$SAVE" -eq 1 ]]; then
		cat - 1>&2
	else
		cat -
	fi
}

get-apk-version() {
	declare release="${1}" mirror="${2:-$MIRROR}" arch="${3:-$ARCH}"
	curl -sSL "${mirror}/${release}/main/${arch}/APKINDEX.tar.gz" \
		| tar -Oxz \
		| grep '^P:apk-tools-static$' -a -A1 \
		| tail -n1 \
		| cut -d: -f2
}

build(){
	declare mirror="$1" rel="$2" timezone="${3:-UTC}"
	local repo="$mirror/$rel/main"

	# tmp
	local tmp="$(mktemp -d "${TMPDIR:-/var/tmp}/alpine-docker-XXXXXXXXXX")"
	local rootfs="$(mktemp -d "${TMPDIR:-/var/tmp}/alpine-docker-rootfs-XXXXXXXXXX")"
	trap 'rm -rf $tmp $rootfs' EXIT TERM INT

	# get apk
	curl -sSL "${repo}/${ARCH}/apk-tools-static-$(get-apk-version "$rel").apk" \
		| tar -xz -C "$tmp" sbin/apk.static

	# mkbase
	"${tmp}/sbin/apk.static" \
		--repository "$repo" \
		--root "$rootfs" \
		--update-cache \
		--allow-untrusted \
		--initdb \
			add alpine-base tzdata
	cp -a "${rootfs}/usr/share/zoneinfo/${timezone}" "${rootfs}/etc/localtime"
	"${tmp}/sbin/apk.static" \
		--root "$rootfs" \
			del tzdata
	rm -f "${rootfs}"/var/cache/apk/*

	# conf
	printf '%s\n' "$repo" > "${rootfs}/etc/apk/repositories"
	[[ "$REPO_EXTRA" ]] && {
		[[ "$rel" == "edge" ]] || printf '%s\n' "@edge $MIRROR/edge/main" >> "${rootfs}/etc/apk/repositories"
		printf '%s\n' "@testing $MIRROR/edge/testing" >> "${rootfs}/etc/apk/repositories"
	}

	[[ "$ADD_APK_SCRIPT" ]] && cp /apk-install "${rootfs}/usr/sbin/apk-install"

	# save
	[[ "$SAVE" ]] && tar -z -f rootfs.tar.gz --numeric-owner -C "$rootfs" -c .
}

main() {
	while getopts "hr:m:t:sec" opt; do
		case $opt in
			r) REL="$OPTARG";;
			m) MIRROR="$OPTARG";;
			s) SAVE=1;;
			e) REPO_EXTRA=1;;
			t) TIMEZONE="$OPTARG";;
			c) ADD_APK_SCRIPT=1;;
			*) usage;;
		esac
	done

	build "$MIRROR" "$REL"
}

main "$@"
