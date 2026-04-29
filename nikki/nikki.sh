#!/bin/sh

opkg() {
opkg update >/dev/null 2>&1
}

nikki() {
wget -O /tmp/nikki/a.ipk https://raw.githubusercontent.com/Razifadm/radu/ipk/nikki/luci-app-nikki_1.26.0-r1_all.ipk >/dev/null 2>&1
wget -O /tmp/nikki/b.ipk https://raw.githubusercontent.com/Razifadm/radu/ipk/nikki/mihomo-meta_1.19.23_aarch64_cortex-a53.ipk >/dev/null 2>&1
wget -O /tmp/nikki/c.ipk https://raw.githubusercontent.com/Razifadm/radu/ipk/nikki/nikki_2026.04.08-r1_aarch64_cortex-a53.ipk >/dev/null 2>&1
wget -O /tmp/nikki/a.ipk https://raw.githubusercontent.com/Razifadm/radu/ipk/nikki/yq_4.52.2-r1_aarch64_cortex-a53.ipk >/dev/null 2>&1
}

main() {
opkg
nikki
opkg install /tmp/nikki/*.ipk
sleep 1
rm -rf /tmp/nikki
}

clear
echo "Installing Nikki"
echo "Currently only RaduImmo.bin support this"
main 
echo ""
echo "Installation Done"
echo ""
echo "access nikki at"
echo "Services-nikki"

exit 0
