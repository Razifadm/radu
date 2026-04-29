#!/bin/sh

IPK_DIR="/tmp/nikki"

LUCIPKG="https://raw.githubusercontent.com/Razifadm/radu/ipk/nikki/luci-app-nikki_1.26.0-r1_all.ipk"
MIHOMO="https://raw.githubusercontent.com/Razifadm/radu/ipk/nikki/mihomo-meta_1.19.23_aarch64_cortex-a53.ipk"
NIKKI="https://raw.githubusercontent.com/Razifadm/radu/ipk/nikki/nikki_2026.04.08-r1_aarch64_cortex-a53.ipk"
YQ="https://raw.githubusercontent.com/Razifadm/radu/ipk/nikki/yq_4.52.2-r1_aarch64_cortex-a53.ipk"

die() {
	echo ""
	echo "ERROR: $1"
	echo ""
	exit 1
}

update_opkg() {
	echo "[1/4] Updating opkg..."
	command opkg update >/dev/null 2>&1 || die "opkg update failed"
}

prepare_dir() {
	rm -rf "$IPK_DIR"
	mkdir -p "$IPK_DIR"
}

download_file() {
	OUT="$1"
	URL="$2"

	echo "Downloading: $OUT"
	wget -q -O "$IPK_DIR/$OUT" "$URL" || die "Download failed: $OUT"

	[ -s "$IPK_DIR/$OUT" ] || die "Downloaded file empty: $OUT"
}

download_nikki() {
	echo "[3/4] Downloading Nikki packages..."

	download_file "luci-app-nikki.ipk" "$LUCIPKG"
	download_file "mihomo-meta.ipk" "$MIHOMO"
	download_file "nikki.ipk" "$NIKKI"
	download_file "yq.ipk" "$YQ"
}

install_nikki() {
	echo "[4/4] Installing Nikki..."

	command opkg install "$IPK_DIR"/*.ipk || die "Nikki installation failed"
}

cleanup() {
	rm -rf "$IPK_DIR"
}

main() {
	clear
	echo "================================"
	echo " Installing Nikki"
	echo " Currently only RaduImmo.bin supported"
	echo "================================"
	echo ""

	update_opkg
	prepare_dir
	download_nikki
	install_nikki
	cleanup

	echo ""
	echo "================================"
	echo " Installation Done"
	echo " Access Nikki at:"
	echo " Services > Nikki"
	echo "================================"
	echo ""
}

main
exit 0
