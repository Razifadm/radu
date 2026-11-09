#!/bin/sh
# rlight-net-menu.sh — BE7000 (MT7531AE switch) LAN/WAN manager
# Detect LAN/WAN ports, promote LAN port to WAN, bandwidth negotiate (ethtool).
# Runtime-only: writes to /etc/config/network via uci, rollback supported.
# No flash/mtd writes. Safe on 5G_modem_Gen2 (OpenWrt 19.07, busybox ash).

SWDEV="switch0"
WAN_IF="ccmni"          # cellular WAN (vendor)
BACKUP="/root/net-menu-backup.conf"

c_g="\\033[32m"; c_y="\\033[33m"; c_r="\\033[31m"; c_b="\\033[36m"; c_0="\\033[0m"

say()  { printf "%b\\n" "$1$c_0"; }
hdr()  { printf "\\n%b=== %s ===%b\\n" "$c_b" "$1" "$c_0"; }

# ---------- detection helpers ----------

# Map switch port -> eth device via kernel: eth0/eth1 are the two GMAC ports.
# Port mapping on this board (MT7531AE): eth0 = switch port 5/6 CPU-facing,
# user ports land on eth0+eth1 via separate GMACs. Detect which eth has carrier.
eth_list() {
    for e in /sys/class/net/eth*; do
        [ -e "$e" ] && basename "$e"
    done
}

eth_carrier() {
    cat "/sys/class/net/$1/carrier" 2>/dev/null
}

eth_speed() {
    cat "/sys/class/net/$1/speed" 2>/dev/null
}

eth_link_mode() {
    ethtool "$1" 2>/dev/null | grep "Speed:" | tr -d '\\t'
}

is_in_lan_br() {
    # bridge membership via kernel
    [ -L "/sys/class/net/br-lan/brif/$1" ] && return 0
    return 1
}

is_in_wan() {
    # ccmni* are always WAN here; check UCI wan ifname contains iface
    uci -q get network.wan.ifname 2>/dev/null | grep -qw "$1" && return 0
    return 1
}

show_ports() {
    hdr "DETECTED PORTS"
    printf "%-10s %-12s %-22s %s\\n" "IFACE" "SPEED" "ROLE" "BRIDGE"
    for e in $(eth_list); do
        car=$(eth_carrier "$e"); [ "$car" = "1" ] && cs="up" || cs="DOWN"
        sp=$(eth_speed "$e"); [ -z "$sp" ] && sp="-"
        [ "$cs" = "DOWN" ] && sp="$sp (down)"
        role="lan"
        is_in_wan "$e" && role="${c_y}wan$c_0"
        [ "$e" = "ccmni1" ] && role="${c_y}wan(cel)$c_0"
        br=""
        is_in_lan_br "$e" && br="br-lan"
        printf "%-10s %-12s %-22s %s\\n" "$e" "$sp Mb" "$role" "$br"
    done
    # cellular
    cel_ip=$(ip -4 addr show ccmni1 2>/dev/null | grep -oE "inet [0-9.]+" | awk '{print $2}')
    say "${c_y}ccmni1 (cellular WAN)${c_0}  ip=$cel_ip"
    # switch detail
    say ""
    say "Switch $SWDEV physical links:"
    swconfig dev $SWDEV show 2>/dev/null | grep "link:" | sed 's/^\\t//' | head -8
    # WAN route
    gw=$(ip route | grep default | head -1)
    say "Default route: $gw"
}

# ---------- role change ----------

backup_netconf() {
    cp /etc/config/network "$BACKUP" 2>/dev/null && say "Backup saved: $BACKUP"
}

promote_lan_to_wan() {
    hdr "PROMOTE LAN PORT -> WAN"
    show_ports
    printf "Which iface to promote (e.g. eth1): "
    read -r IF
    [ -z "$IF" ] && { say "cancelled"; return; }
    if ! [ -e "/sys/class/net/$IF" ]; then say "${c_r}no such iface$c_0"; return; fi
    if [ "$IF" = "ccmni1" ]; then say "${c_r}refusing: cellular WAN$c_0"; return; fi

    backup_netconf

    # 1) remove from LAN bridge (uci + live)
    if is_in_lan_br "$IF"; then
        brctl delif br-lan "$IF" 2>/dev/null
        uci -q del_list network.lan.ifname="$IF"
        uci -q set network.lan.ifname="$(uci -q get network.lan.ifname | tr ' ' '\\n' | grep -vx "$IF" | tr '\\n' ' ' | sed 's/ $//')"
    fi

    # 2) add to wan ifname list (multiwan-safe: keep ccmni)
    uci -q add_list network.wan.ifname="$IF"

    # 3) live apply: wan iface gets dhcp client
    ip addr flush dev "$IF" 2>/dev/null
    uci commit network
    /etc/init.d/network reload 2>/dev/null || /etc/init.d/network restart
    say "${c_g}$IF promoted to WAN (dhcp). Reload done.$c_0"
    say "Check: ip addr show $IF"
}

demote_wan_to_lan() {
    hdr "DEMOTE WAN PORT -> LAN"
    printf "Which iface to demote (e.g. eth1): "
    read -r IF
    [ -z "$IF" ] && { say "cancelled"; return; }
    backup_netconf
    uci -q del_list network.wan.ifname="$IF"
    uci -q add_list network.lan.ifname="$IF"
    uci commit network
    brctl addif br-lan "$IF" 2>/dev/null
    /etc/init.d/network reload 2>/dev/null || /etc/init.d/network restart
    say "${c_g}$IF demoted to LAN bridge.$c_0"
}

rollback() {
    [ -f "$BACKUP" ] || { say "${c_r}no backup$c_0"; return; }
    cp "$BACKUP" /etc/config/network
    /etc/init.d/network restart
    say "${c_g}rolled back to $BACKUP$c_0"
}

# ---------- bandwidth negotiation (ethtool) ----------

bw_menu() {
    hdr "BANDWIDTH NEGOTIATION (ethtool)"
    printf "Interface (eth0/eth1): "
    read -r IF
    [ -e "/sys/class/net/$IF" ] || { say "${c_r}no such iface$c_0"; return; }
    say "Current: $(eth_link_mode "$IF")"
    say "1) Auto-negotiate (recommended)"
    say "2) Force 1000Full"
    say "3) Force 100Full"
    say "4) Force 10Full"
    say "5) Show advertised capabilities"
    printf "Choice: "
    read -r C
    case "$C" in
        1) ethtool -s "$IF" autoneg on && say "${c_g}autoneg on$c_0" ;;
        2) ethtool -s "$IF" autoneg off speed 1000 duplex full && say "${c_g}forced 1000F$c_0" ;;
        3) ethtool -s "$IF" autoneg off speed 100 duplex full && say "${c_g}forced 100F$c_0" ;;
        4) ethtool -s "$IF" autoneg off speed 10 duplex full && say "${c_g}forced 10F$c_0" ;;
        5) ethtool "$IF" | sed -n '/Supported link modes/,/Auto-negotiation/p' ;;
        *) say "cancelled" ;;
    esac
    say "Verify: $(eth_link_mode "$IF")"
}

# ---------- VLAN port split (the REAL way to separate RJ45 ports) ----------
# Board reality: all 5 RJ45 hang off MT7531 switch -> GMAC0 (eth0). eth1 is a
# second GMAC with no external RJ45. To give each RJ45 its own interface:
# enable switch VLAN, map one switch port per VLAN, create eth0.<vid>.
# Reversible: rollback deletes subifs + disables vlan mode.

vlan_split_menu() {
    hdr "VLAN PORT SPLIT (per-RJ45 interfaces)"
    say "Board: 5x RJ45 = switch ports 0-4 (via eth0). CPU port = 6."
    say "This creates eth0.<vid> interfaces, one per selected port."
    say "${c_y}NOTE: split ports leave br-lan — your connected LAN port must stay bridged$c_0"
    say ""
    show_ports
    say ""
    say "1) Split ONE port out (e.g. port 4 -> eth0.104 as new interface)"
    say "2) Full split: all 5 ports separate (eth0.100..eth0.104)"
    say "3) Undo split (restore single-bridge mode)"
    say "0) back"
    printf "Choice: "
    read -r C
    case "$C" in
        1)
            printf "Switch port to split (0-4): "
            read -r SP
            case "$SP" in 0|1|2|3|4) ;; *) say "invalid"; return ;; esac
            VID=$((100 + SP))
            backup_netconf
            swconfig dev switch0 set enable_vlan 1
            # keep remaining ports + cpu in vlan 1 (lan), target port alone in its vlan
            REMAIN=""
            for p in 0 1 2 3 4; do [ "$p" != "$SP" ] && REMAIN="$REMAIN $p"; done
            swconfig dev switch0 vlan 1 set ports "$REMAIN 6"
            swconfig dev switch0 vlan $VID set ports "$SP 6"
            swconfig dev switch0 apply
            ip link add link eth0 name eth0.$VID type vlan id $VID 2>/dev/null
            ip link set eth0.$VID up
            # uci: remove port's eth0 from lan, add vlan iface with dhcp
            uci -q set network.lan.ifname="$(uci -q get network.lan.ifname | tr ' ' '\n' | grep -vx eth0 | tr '\n' ' ' | sed 's/ $//')"
            # eth0 stays in lan via vlan 1 as eth0.1 concept — simpler: keep eth0 bridged
            uci -q add_list network.lan.ifname="eth0"
            uci -q set network.lan.ifname="$(uci -q get network.lan.ifname | tr ' ' '\n' | sort -u | tr '\n' ' ' | sed 's/ $//')"
            uci set network.lanwan$VID=interface
            uci set network.lanwan$VID.proto='dhcp'
            uci set network.lanwan$VID.ifname="eth0.$VID"
            uci commit network
            say "${c_g}Port $SP split out as eth0.$VID (interface lanwan$VID, dhcp).$c_0"
            say "It is NOT in wan yet — use menu 2 to promote, or edit proto in LuCI."
            ;;
        2)
            backup_netconf
            swconfig dev switch0 set enable_vlan 1
            swconfig dev switch0 vlan 1 set ports "6"
            for p in 0 1 2 3 4; do
                VID=$((100 + p))
                swconfig dev switch0 vlan $VID set ports "$p 6"
                ip link add link eth0 name eth0.$VID type vlan id $VID 2>/dev/null
                ip link set eth0.$VID up
            done
            swconfig dev switch0 apply
            brctl delif br-lan eth0 2>/dev/null
            uci -q set network.lan.ifname="eth1 rndis0"
            for p in 0 1 2 3 4; do
                VID=$((100 + p))
                uci set network.lanwan$VID=interface
                uci set network.lanwan$VID.proto='dhcp'
                uci set network.lanwan$VID.ifname="eth0.$VID"
            done
            uci commit network
            /etc/init.d/network reload 2>/dev/null || /etc/init.d/network restart
            say "${c_g}All 5 ports split: eth0.100..eth0.104 (lanwan100..104, dhcp).$c_0"
            say "${c_y}WARNING: eth0 left br-lan. If you were connected via RJ45 LAN,${c_0}"
            say "${c_y}you are now on eth0.100 (dhcp) — reconnect may be needed.$c_0"
            ;;
        3)
            backup_netconf
            for p in 0 1 2 3 4; do ip link del eth0.$((100+p)) 2>/dev/null; done
            swconfig dev switch0 set enable_vlan 0
            swconfig dev switch0 apply
            brctl addif br-lan eth0 2>/dev/null
            uci -q set network.lan.ifname="eth0 eth1 rndis0"
            for p in 0 1 2 3 4; do uci -q delete network.lanwan$((100+p)); done
            uci commit network
            /etc/init.d/network reload 2>/dev/null || /etc/init.d/network restart
            say "${c_g}Split undone — single bridge restored.$c_0"
            ;;
        *) say "back" ;;
    esac
}

# ---------- main menu ----------

while :; do
    hdr "NET MENU — 5G_modem_Gen2"
    say "1) Detect ports (LAN/WAN/carrier/speed)"
    say "2) Promote LAN port -> WAN"
    say "3) Demote WAN port -> LAN"
    say "4) Bandwidth negotiate (ethtool)"
    say "5) VLAN split: RJ45 ports as separate interfaces"
    say "6) Rollback network config"
    say "0) Exit"
    printf "Choice: "
    read -r C
    case "$C" in
        1) show_ports ;;
        2) promote_lan_to_wan ;;
        3) demote_wan_to_lan ;;
        4) bw_menu ;;
        5) vlan_split_menu ;;
        6) rollback ;;
        0|q) break ;;
        *) say "invalid" ;;
    esac
done
