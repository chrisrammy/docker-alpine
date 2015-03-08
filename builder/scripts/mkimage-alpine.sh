#!/bin/sh

# This mkimage-alpine.sh is a modified version from
# https://github.com/docker/docker/blob/master/contrib/mkimage-alpine.sh.
# Changes were inspired by work done by Eivind Uggedal (uggedal) and
# Luis Lavena (luislavena).

set -e
[ "$TRACE" ] && set -x

[ "$(id -u)" -eq 0 ] || {
	printf >&2 '%s requires root\n' "$0"
	exit 1
}

usage() {
	printf >&2 '%s: [-r release] [-m mirror] [-s] [-e] [-c] [-t]\n' "$0"
	exit 1
}

tmp() {
	TMP="$(mktemp -d "${TMPDIR:-/var/tmp}/alpine-docker-XXXXXXXXXX")"
	ROOTFS="$(mktemp -d "${TMPDIR:-/var/tmp}/alpine-docker-rootfs-XXXXXXXXXX")"
	trap 'rm -rf $TMP $ROOTFS' EXIT TERM INT
}

apkv() {
	curl -sSL "${REPO}/${ARCH}/APKINDEX.tar.gz" | tar -Oxz |
		grep '^P:apk-tools-static$' -a -A1 | tail -n1 | cut -d: -f2
}

getapk() {
	local version="$(apkv)"
	curl -sSL "${REPO}/${ARCH}/apk-tools-static-${version}.apk" |
		tar -xz -C "$TMP" sbin/apk.static
}

mkbase() {
	"${TMP}/sbin/apk.static" --repository "$REPO" --update-cache --allow-untrusted \
		--root "$ROOTFS" --initdb add alpine-base
}

timezone() {
	local timezone="${1:-UTC}"

	"${TMP}/sbin/apk.static" \
		--repository "$REPO" \
		--update-cache \
		--allow-untrusted \
		--root "$ROOTFS" \
		--initdb add tzdata
	cp -a "${ROOTFS}/usr/share/zoneinfo/${timezone}" "${ROOTFS}/etc/localtime"
	"${TMP}/sbin/apk.static" \
		--root "$ROOTFS" \
		del tzdata
}

conf() {
	printf '%s\n' "$REPO" > "${ROOTFS}/etc/apk/repositories"
	[ "$REPO_EXTRA" -eq 1 ] && {
		[ "$REL" = "edge" ] || printf '%s\n' "@edge $MIRROR/edge/main" >> "${ROOTFS}/etc/apk/repositories"
		printf '%s\n' "@testing $MIRROR/edge/testing" >> "${ROOTFS}/etc/apk/repositories"
	}
	[ "$ADD_APK_SCRIPT" -eq 1 ] && cp /apk-install "${ROOTFS}/usr/sbin/apk-install"
	timezone "UTC"
	rm -f "$ROOTFS"/var/cache/apk/*
}

save() {
	[ "$SAVE" -eq 1 ] || return

	tar -z -f rootfs.tar.gz --numeric-owner -C "$ROOTFS" -c .
}

while getopts "hr:m:t:sec" opt; do
	case $opt in
		r)
			REL="$OPTARG"
			;;
		m)
			MIRROR="$OPTARG"
			;;
		s)
			SAVE=1
			;;
		e)
			REPO_EXTRA=1
			;;
		t)
			TIMEZONE="$OPTARG"
			;;
		c)
			ADD_APK_SCRIPT=1
			;;
		*)
			usage
			;;
	esac
done

REL="${REL:-edge}"
MIRROR="${MIRROR:-http://nl.alpinelinux.org/alpine}"
SAVE="${SAVE:-0}"
ADD_APK_SCRIPT="${ADD_APK_SCRIPT:-0}"
TIMEZONE="${TIMEZONE:-UTC}"
REPO="$MIRROR/$REL/main"
REPO_EXTRA="${REPO_EXTRA:-0}"
ARCH="$(uname -m)"

tmp 1>&2 && getapk 1>&2 && mkbase 1>&2 && conf 1>&2 && save
