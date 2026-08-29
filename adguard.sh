#!/bin/sh
#
# AdGuard Home OpenWrt Installer
# Author: Raducksijaa
#
# Usage:
#   sh adguard-install.sh install
#   sh adguard-install.sh uninstall
#   sh adguard-install.sh status
#
# Design:
#   AdGuard Home :53
#   dnsmasq      :54
#   LAN clients  -> Router LAN IP :53
#   dnsmasq      -> 127.0.0.1#53
#

set -u

SCRIPT_NAME="adguard-install.sh"
BACKUP_DIR="/etc/adguardhome-preinstall"
DHCP_BACKUP="$BACKUP_DIR/dhcp"
STATE_FILE="$BACKUP_DIR/state"
DNSMASQ_PORT="54"
ADGUARD_DNS_PORT="53"
ADGUARD_WEB_PORT="3000"

ADGUARD_INSTALLER="https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh"

# ============================================================
# COLORS
# ============================================================

if [ -t 1 ]; then
    RED='\033[31m'
    GREEN='\033[32m'
    YELLOW='\033[33m'
    BLUE='\033[34m'
    CYAN='\033[36m'
    RESET='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    RESET=''
fi

info() {
    printf "${CYAN}[INFO]${RESET} %s\n" "$*"
}

ok() {
    printf "${GREEN}[OK]${RESET} %s\n" "$*"
}

warn() {
    printf "${YELLOW}[WARN]${RESET} %s\n" "$*"
}

die() {
    printf "${RED}[ERROR]${RESET} %s\n" "$*" >&2
    exit 1
}

# ============================================================
# HELPERS
# ============================================================

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

require_root() {
    [ "$(id -u 2>/dev/null)" = "0" ] || die "Run this script as root."
}

require_openwrt() {
    command_exists uci || die "uci not found. This script is intended for OpenWrt."
    [ -f /etc/config/dhcp ] || die "/etc/config/dhcp not found."
}

get_lan_ip() {
    local ip=""

    # OpenWrt modern
    if command_exists ubus; then
        ip="$(
            ubus call network.interface.lan status 2>/dev/null |
            sed -n 's/.*"address":[[:space:]]*"\([^"]*\)".*/\1/p' |
            head -n1
        )"
    fi

    # UCI static address fallback
    if [ -z "$ip" ]; then
        ip="$(uci -q get network.lan.ipaddr 2>/dev/null | head -n1)"
    fi

    # ip command fallback
    if [ -z "$ip" ] && command_exists ip; then
        ip="$(
            ip -4 addr show br-lan 2>/dev/null |
            awk '/inet / {sub(/\/.*/, "", $2); print $2; exit}'
        )"
    fi

    # Older ifconfig fallback
    if [ -z "$ip" ] && command_exists ifconfig; then
        ip="$(
            ifconfig br-lan 2>/dev/null |
            sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p' |
            head -n1
        )"
    fi

    printf '%s\n' "$ip"
}

restart_dnsmasq() {
    if [ -x /etc/init.d/dnsmasq ]; then
        /etc/init.d/dnsmasq restart >/dev/null 2>&1 ||
            /etc/init.d/dnsmasq start >/dev/null 2>&1 ||
            return 1
    else
        return 1
    fi

    return 0
}

find_adguard_binary() {
    for p in \
        /opt/AdGuardHome/AdGuardHome \
        /usr/local/AdGuardHome/AdGuardHome \
        /root/AdGuardHome/AdGuardHome \
        /AdGuardHome/AdGuardHome
    do
        [ -x "$p" ] && {
            printf '%s\n' "$p"
            return 0
        }
    done

    p="$(command -v AdGuardHome 2>/dev/null || true)"
    [ -n "$p" ] && {
        printf '%s\n' "$p"
        return 0
    }

    return 1
}

find_adguard_dir() {
    local bin

    bin="$(find_adguard_binary 2>/dev/null || true)"

    if [ -n "$bin" ]; then
        dirname "$bin"
        return 0
    fi

    return 1
}

adguard_service_exists() {
    [ -x /etc/init.d/AdGuardHome ] ||
    [ -x /etc/init.d/adguardhome ] ||
    find_adguard_binary >/dev/null 2>&1
}

start_adguard() {
    if [ -x /etc/init.d/AdGuardHome ]; then
        /etc/init.d/AdGuardHome enable >/dev/null 2>&1 || true
        /etc/init.d/AdGuardHome restart >/dev/null 2>&1 ||
            /etc/init.d/AdGuardHome start >/dev/null 2>&1 ||
            return 1
        return 0
    fi

    if [ -x /etc/init.d/adguardhome ]; then
        /etc/init.d/adguardhome enable >/dev/null 2>&1 || true
        /etc/init.d/adguardhome restart >/dev/null 2>&1 ||
            /etc/init.d/adguardhome start >/dev/null 2>&1 ||
            return 1
        return 0
    fi

    local bin
    bin="$(find_adguard_binary 2>/dev/null || true)"

    [ -n "$bin" ] || return 1

    "$bin" -s install >/dev/null 2>&1 || true

    if [ -x /etc/init.d/AdGuardHome ]; then
        /etc/init.d/AdGuardHome enable >/dev/null 2>&1 || true
        /etc/init.d/AdGuardHome start >/dev/null 2>&1 || true
    fi

    return 0
}

stop_adguard() {
    if [ -x /etc/init.d/AdGuardHome ]; then
        /etc/init.d/AdGuardHome stop >/dev/null 2>&1 || true
        /etc/init.d/AdGuardHome disable >/dev/null 2>&1 || true
    fi

    if [ -x /etc/init.d/adguardhome ]; then
        /etc/init.d/adguardhome stop >/dev/null 2>&1 || true
        /etc/init.d/adguardhome disable >/dev/null 2>&1 || true
    fi
}

port_listening() {
    local port="$1"

    if command_exists ss; then
        ss -lnut 2>/dev/null |
            awk '{print $5}' |
            grep -E "[:.]${port}$" >/dev/null 2>&1
        return $?
    fi

    if command_exists netstat; then
        netstat -lnut 2>/dev/null |
            awk '{print $4}' |
            grep -E "[:.]${port}$" >/dev/null 2>&1
        return $?
    fi

    return 2
}

# ============================================================
# DHCP OPTION HANDLING
# ============================================================

#
# Preserve all existing DHCP options except option 6.
#
set_lan_dns_option() {
    local lan_ip="$1"
    local values value

    values="$(uci -q get dhcp.lan.dhcp_option 2>/dev/null || true)"

    uci -q delete dhcp.lan.dhcp_option 2>/dev/null || true

    for value in $values; do
        case "$value" in
            6,*)
                # Replace existing DNS option.
                ;;
            *)
                uci add_list dhcp.lan.dhcp_option="$value"
                ;;
        esac
    done

    uci add_list dhcp.lan.dhcp_option="6,$lan_ip"
}

#
# Preserve existing dnsmasq upstreams except an existing
# 127.0.0.1#53 entry, avoiding duplicates.
#
set_dnsmasq_adguard_upstream() {
    local values value

    values="$(uci -q get dhcp.@dnsmasq[0].server 2>/dev/null || true)"

    uci -q delete dhcp.@dnsmasq[0].server 2>/dev/null || true

    for value in $values; do
        [ "$value" = "127.0.0.1#53" ] && continue
        uci add_list dhcp.@dnsmasq[0].server="$value"
    done

    uci add_list dhcp.@dnsmasq[0].server="127.0.0.1#53"
}

# ============================================================
# BACKUP
# ============================================================

create_backup() {
    if [ -f "$DHCP_BACKUP" ]; then
        ok "Existing pre-install backup found."
        return 0
    fi

    mkdir -p "$BACKUP_DIR" || die "Cannot create $BACKUP_DIR"

    cp -p /etc/config/dhcp "$DHCP_BACKUP" ||
        die "Unable to backup /etc/config/dhcp"

    cat >"$STATE_FILE" <<EOF
DNSMASQ_PORT=$DNSMASQ_PORT
ADGUARD_DNS_PORT=$ADGUARD_DNS_PORT
ADGUARD_WEB_PORT=$ADGUARD_WEB_PORT
EOF

    sync

    ok "Original dnsmasq config backed up."
}

restore_backup() {
    [ -f "$DHCP_BACKUP" ] || return 1

    cp -p "$DHCP_BACKUP" /etc/config/dhcp ||
        die "Failed restoring original /etc/config/dhcp"

    sync

    return 0
}

# ============================================================
# INSTALL ADGUARD
# ============================================================

install_adguard() {
    if find_adguard_binary >/dev/null 2>&1; then
        ok "AdGuard Home already installed."
        start_adguard || warn "Unable to restart AdGuard Home."
        return 0
    fi

    info "Installing AdGuard Home..."

    if command_exists curl; then
        curl -s -S -L "$ADGUARD_INSTALLER" |
            sh -s -- -v ||
            die "AdGuard Home installer failed."

    elif command_exists wget; then
        wget -qO- "$ADGUARD_INSTALLER" |
            sh -s -- -v ||
            die "AdGuard Home installer failed."

    else
        die "Neither curl nor wget is installed."
    fi

    find_adguard_binary >/dev/null 2>&1 ||
        die "AdGuard Home installer completed but binary was not found."

    start_adguard || warn "AdGuard installed but service restart failed."

    ok "AdGuard Home installed."
}

# ============================================================
# REMOVE ADGUARD
# ============================================================

remove_adguard() {
    local bin dir

    bin="$(find_adguard_binary 2>/dev/null || true)"
    dir="$(find_adguard_dir 2>/dev/null || true)"

    stop_adguard

    if [ -n "$bin" ]; then
        info "Removing AdGuard Home..."

        "$bin" -s uninstall >/dev/null 2>&1 || true
    fi

    #
    # Official installer usually installs into /opt/AdGuardHome.
    # Only remove known AdGuard installation directories.
    #
    case "$dir" in
        /opt/AdGuardHome|/usr/local/AdGuardHome|/root/AdGuardHome|/AdGuardHome)
            rm -rf "$dir"
            ;;
    esac

    rm -f /etc/init.d/AdGuardHome
    rm -f /etc/init.d/adguardhome

    ok "AdGuard Home removed."
}

# ============================================================
# CONFIGURE OPENWRT
# ============================================================

configure_dnsmasq() {
    local lan_ip="$1"

    info "Moving dnsmasq from port 53 to $DNSMASQ_PORT..."

    uci set dhcp.@dnsmasq[0].port="$DNSMASQ_PORT" ||
        die "Unable to set dnsmasq port."

    #
    # Required for controlled upstream.
    #
    uci set dhcp.@dnsmasq[0].noresolv='1' ||
        die "Unable to set dnsmasq noresolv."

    set_dnsmasq_adguard_upstream

    #
    # LAN DHCP clients receive router LAN address as DNS.
    #
    set_lan_dns_option "$lan_ip"

    uci commit dhcp ||
        die "Failed committing DHCP configuration."

    restart_dnsmasq ||
        die "dnsmasq failed to restart."

    ok "dnsmasq configured on port $DNSMASQ_PORT."
}

# ============================================================
# STATUS
# ============================================================

show_summary() {
    local lan_ip ag_dir
    local dns_state="UNKNOWN"
    local dnsmasq_state="UNKNOWN"
    local web_state="UNKNOWN"

    lan_ip="$(get_lan_ip)"
    [ -n "$lan_ip" ] || lan_ip="LAN-IP"

    ag_dir="$(find_adguard_dir 2>/dev/null || true)"
    [ -n "$ag_dir" ] || ag_dir="Not detected"

    if port_listening "$ADGUARD_DNS_PORT"; then
        dns_state="LISTENING"
    else
        case "$?" in
            2) dns_state="CHECK UNAVAILABLE" ;;
            *) dns_state="NOT LISTENING" ;;
        esac
    fi

    if port_listening "$DNSMASQ_PORT"; then
        dnsmasq_state="LISTENING"
    else
        case "$?" in
            2) dnsmasq_state="CHECK UNAVAILABLE" ;;
            *) dnsmasq_state="NOT LISTENING" ;;
        esac
    fi

    if port_listening "$ADGUARD_WEB_PORT"; then
        web_state="LISTENING"
    else
        case "$?" in
            2) web_state="CHECK UNAVAILABLE" ;;
            *) web_state="SETUP / NOT LISTENING" ;;
        esac
    fi

    printf '\n'
    printf '============================================================\n'
    printf ' AdGuard Home OpenWrt\n'
    printf '============================================================\n'
    printf ' WebUI          : http://%s:%s\n' "$lan_ip" "$ADGUARD_WEB_PORT"
    printf ' WebUI status   : %s\n' "$web_state"
    printf '\n'
    printf ' AdGuard DNS    : %s:%s\n' "$lan_ip" "$ADGUARD_DNS_PORT"
    printf ' DNS status     : %s\n' "$dns_state"
    printf '\n'
    printf ' dnsmasq        : 127.0.0.1:%s\n' "$DNSMASQ_PORT"
    printf ' dnsmasq status : %s\n' "$dnsmasq_state"
    printf '\n'
    printf ' DHCP DNS       : %s\n' "$lan_ip"
    printf ' AdGuard path   : %s\n' "$ag_dir"
    printf '\n'
    printf ' Credentials    : Configure via AdGuard WebUI\n'
    printf '                  Username/password are not preset here.\n'
    printf '============================================================\n'
}

show_status() {
    local lan_ip

    lan_ip="$(get_lan_ip)"
    [ -n "$lan_ip" ] || lan_ip="unknown"

    printf '\n'
    printf 'AdGuard Home status\n'
    printf '-------------------\n'
    printf 'LAN IP       : %s\n' "$lan_ip"
    printf 'dnsmasq port : %s\n' "$(uci -q get dhcp.@dnsmasq[0].port 2>/dev/null || echo default)"
    printf 'noresolv     : %s\n' "$(uci -q get dhcp.@dnsmasq[0].noresolv 2>/dev/null || echo 0)"
    printf 'DHCP option  : %s\n' "$(uci -q get dhcp.lan.dhcp_option 2>/dev/null || echo none)"

    if find_adguard_binary >/dev/null 2>&1; then
        printf 'AdGuard Home : INSTALLED\n'
    else
        printf 'AdGuard Home : NOT INSTALLED\n'
    fi

    [ -f "$DHCP_BACKUP" ] &&
        printf 'Backup       : %s\n' "$DHCP_BACKUP" ||
        printf 'Backup       : NONE\n'

    printf '\n'
}

# ============================================================
# INSTALL
# ============================================================

do_install() {
    local lan_ip

    require_root
    require_openwrt

    lan_ip="$(get_lan_ip)"

    [ -n "$lan_ip" ] ||
        die "Unable to detect LAN IPv4 address."

    info "Detected LAN IP: $lan_ip"

    #
    # Backup MUST happen before modifying UCI.
    #
    create_backup

    #
    # Install AdGuard while dnsmasq may still own :53.
    #
    # AdGuard initial installer itself does not need to bind its
    # final DNS listener before WebUI setup.
    #
    install_adguard

    #
    # Free :53 for AdGuard and point dnsmasq upstream to AdGuard.
    #
    configure_dnsmasq "$lan_ip"

    #
    # Restart AdGuard after port 53 becomes free.
    #
    start_adguard || warn "Could not explicitly restart AdGuard Home."

    sleep 1

    printf '\n'
    ok "Installation flow completed."

    show_summary
}

# ============================================================
# UNINSTALL
# ============================================================

do_uninstall() {
    require_root
    require_openwrt

    printf '\n'
    info "Starting AdGuard Home rollback..."

    #
    # Stop AdGuard first so native DNS can reclaim :53.
    #
    stop_adguard

    if restore_backup; then
        ok "Original /etc/config/dhcp restored."

        restart_dnsmasq ||
            die "Original DHCP config restored but dnsmasq failed to restart."

        ok "dnsmasq restarted using original configuration."
    else
        warn "No pre-install DHCP backup found."

        #
        # Safety fallback. Only do this when no exact backup exists.
        #
        info "Applying fallback native dnsmasq configuration..."

        uci set dhcp.@dnsmasq[0].port='53'
        uci -q delete dhcp.@dnsmasq[0].noresolv 2>/dev/null || true

        #
        # Remove our localhost AdGuard upstream only.
        #
        old_servers="$(uci -q get dhcp.@dnsmasq[0].server 2>/dev/null || true)"

        if [ -n "$old_servers" ]; then
            uci -q delete dhcp.@dnsmasq[0].server 2>/dev/null || true

            for server in $old_servers; do
                [ "$server" = "127.0.0.1#53" ] && continue
                uci add_list dhcp.@dnsmasq[0].server="$server"
            done
        fi

        uci commit dhcp

        restart_dnsmasq ||
            die "Failed to restore dnsmasq."
    fi

    remove_adguard

    #
    # Remove backup only after successful restore.
    #
    if [ -f "$DHCP_BACKUP" ]; then
        rm -rf "$BACKUP_DIR"
        ok "Pre-install backup removed."
    fi

    printf '\n'
    printf '============================================================\n'
    printf ' AdGuard Home removed\n'
    printf '============================================================\n'
    printf ' dnsmasq configuration : RESTORED\n'
    printf ' AdGuard Home          : REMOVED\n'
    printf ' Native router DNS     : ACTIVE\n'
    printf '============================================================\n'
    printf '\n'
}

# ============================================================
# USAGE
# ============================================================

usage() {
    cat <<EOF

AdGuard Home OpenWrt Installer

Usage:

  $SCRIPT_NAME install
  $SCRIPT_NAME uninstall
  $SCRIPT_NAME status

Install architecture:

  LAN clients
       |
       | DNS :53
       v
  AdGuard Home :53
       |
       v
  dnsmasq :54

Default ports:

  AdGuard DNS : 53
  dnsmasq     : 54
  AdGuard UI  : 3000

EOF
}

# ============================================================
# MAIN
# ============================================================

ACTION="${1:-}"

case "$ACTION" in
    install)
        do_install
        ;;

    uninstall|remove)
        do_uninstall
        ;;

    status)
        require_root
        require_openwrt
        show_status
        ;;

    help|-h|--help|"")
        usage
        ;;

    *)
        die "Unknown command: $ACTION"
        ;;
esac

exit 0
