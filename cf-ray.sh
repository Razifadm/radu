#!/bin/sh

set -u

CORE_NAME='xraycore26'
SOURCE_URL="${1:-https://raw.githubusercontent.com/Razifadm/radu/main/xraycore26}"
# GitHub's "tree/main" link is a browser view; executables must use "raw".
UNZIP_URL='https://raw.githubusercontent.com/Razifadm/radu/main/usr/bin/rlight-deps/aarch64/rlight-unzip-aarch64'

TARGET='/usr/bin/strxcore'
XRAY_LINK='/usr/bin/xray'
UCI_XRAY_PATH='/usr/bin/xray'
BACKUP_CORE="/usr/bin/.strxcore.backup.$$"
BACKUP_XRAY="/usr/bin/.xray.backup.$$"
STAGED="/usr/bin/.strxcore.new.$$"

WORKDIR=$(mktemp -d /tmp/strx-update.XXXXXX) || {
    echo 'ERROR: Cannot create /tmp working directory.' >&2
    exit 1
}
DOWNLOAD="$WORKDIR/download"
EXTRACT="$WORKDIR/extracted"
HELPER="$WORKDIR/rlight-unzip-aarch64"

MOVED_CORE=0
MOVED_XRAY=0
NEW_CORE=0
NEW_XRAY=0
SUCCESS=0
UCI_CHANGED_PASSWALL=0
UCI_CHANGED_PASSWALL2=0
UNZIP_KIND=''

fail() { echo "ERROR: $*" >&2; exit 1; }

cleanup_and_rollback() {
    rc=$?
    trap - 0 1 2 3 15
    if [ "$SUCCESS" -ne 1 ]; then
        if [ "$NEW_XRAY" -eq 1 ]; then rm -f "$XRAY_LINK"; fi
        if [ "$MOVED_XRAY" -eq 1 ]; then
            rm -f "$XRAY_LINK"
            mv -f "$BACKUP_XRAY" "$XRAY_LINK" || echo 'WARNING: Cannot restore old xray.' >&2
        fi
        if [ "$NEW_CORE" -eq 1 ]; then rm -f "$TARGET"; fi
        if [ "$MOVED_CORE" -eq 1 ]; then
            rm -f "$TARGET"
            mv -f "$BACKUP_CORE" "$TARGET" || echo 'WARNING: Cannot restore old strxcore.' >&2
        fi
        for svc in passwall passwall2; do
            changed=0
            case "$svc" in
                passwall) changed=$UCI_CHANGED_PASSWALL ;;
                passwall2) changed=$UCI_CHANGED_PASSWALL2 ;;
            esac
            if [ "$changed" -eq 1 ] && [ -f "$WORKDIR/$svc.config" ]; then
                cp -p "$WORKDIR/$svc.config" "/etc/config/$svc" || \
                    echo "WARNING: Cannot restore $svc config." >&2
                uci -q revert "$svc" >/dev/null 2>&1 || :
            fi
        done
    fi
    rm -f "$STAGED"
    rm -rf "$WORKDIR"
    exit "$rc"
}
trap cleanup_and_rollback 0
trap 'exit 1' 1 2 3 15

# Both downloader methods are supported. Never continue with a partial file.
download_file() {
    url=$1
    dest=$2
    rm -f "$dest"
    if command -v wget >/dev/null 2>&1; then
        if wget -O "$dest" "$url" && [ -s "$dest" ]; then return 0; fi
        rm -f "$dest"
        echo 'WARNING: wget failed; trying curl (if installed).' >&2
    fi
    if command -v curl >/dev/null 2>&1; then
        if curl -fL -o "$dest" "$url" && [ -s "$dest" ]; then return 0; fi
        rm -f "$dest"
    fi
    return 1
}

# BusyBox applet may exist even without an "unzip" command/symlink.
unzip_run() {
    case "$UNZIP_KIND" in
        native) unzip "$@" ;;
        busybox) busybox unzip "$@" ;;
        helper) "$HELPER" "$@" ;;
        *) return 127 ;;
    esac
}

ensure_unzip() {
    if command -v unzip >/dev/null 2>&1; then
        UNZIP_KIND='native'
        return 0
    fi
    if command -v busybox >/dev/null 2>&1 && \
       busybox --list 2>/dev/null | grep -qx unzip; then
        UNZIP_KIND='busybox'
        return 0
    fi
    arch=$(uname -m 2>/dev/null || echo unknown)
    case "$arch" in
        aarch64|arm64) ;;
        *) fail "unzip missing; bundled helper is aarch64 only (router: $arch). Install unzip for this architecture." ;;
    esac
    echo "No unzip installed; downloading aarch64 helper: $UNZIP_URL"
    download_file "$UNZIP_URL" "$HELPER" || fail 'Cannot download unzip helper.'
    chmod 700 "$HELPER" || fail 'Cannot execute unzip helper.'
    UNZIP_KIND='helper'
}

command -v uci >/dev/null 2>&1 || fail 'uci is not installed.'
[ ! -e "$BACKUP_CORE" ] && [ ! -L "$BACKUP_CORE" ] || fail "Backup path exists: $BACKUP_CORE"
[ ! -e "$BACKUP_XRAY" ] && [ ! -L "$BACKUP_XRAY" ] || fail "Backup path exists: $BACKUP_XRAY"
[ ! -e "$STAGED" ] && [ ! -L "$STAGED" ] || fail "Staging path exists: $STAGED"

echo "Downloading $CORE_NAME from: $SOURCE_URL"
download_file "$SOURCE_URL" "$DOWNLOAD" || fail 'Download failed or file is empty.'

CANDIDATE="$DOWNLOAD"
# ZIP local-file headers start with PK (raw ELF binaries do not). Do not require
# unzip for a plain executable, including the current xraycore26 source.
signature=$(dd if="$DOWNLOAD" bs=2 count=1 2>/dev/null)
if [ "$signature" = 'PK' ]; then
    echo 'ZIP detected; preparing extraction.'
    ensure_unzip
    unzip_run -t "$DOWNLOAD" >/dev/null 2>&1 || fail 'ZIP is corrupt or unzip helper cannot read it.'
    mkdir -p "$EXTRACT" || fail 'Cannot create extraction directory.'
    unzip_run -o -q "$DOWNLOAD" -d "$EXTRACT" || fail 'ZIP extraction failed.'
    CANDIDATE=$(find "$EXTRACT" -type f \( -name xray -o -name xray26 -o -name strxcore -o -name xraycore26 \) -print | head -n 1)
    [ -n "$CANDIDATE" ] || fail 'ZIP contains no recognized Xray executable.'
fi

chmod +x "$CANDIDATE" || fail 'Cannot mark downloaded binary executable.'
if ! "$CANDIDATE" version >/dev/null 2>&1 && \
   ! "$CANDIDATE" --version >/dev/null 2>&1; then
    fail 'Core validation failed (wrong architecture, missing libraries, or not an Xray core).'
fi

echo 'Binary validated; preparing installation.'
for svc in passwall passwall2; do
    if [ -f "/etc/config/$svc" ]; then
        cp -p "/etc/config/$svc" "$WORKDIR/$svc.config" || fail "Cannot back up $svc config."
    fi
done

# Stage on the same filesystem as /usr/bin before replacing existing binaries.
cp "$CANDIDATE" "$STAGED" || fail 'Cannot stage new binary; check /usr storage.'
chmod 755 "$STAGED" || fail 'Cannot set staged binary permissions.'

if [ -e "$TARGET" ] || [ -L "$TARGET" ]; then
    mv "$TARGET" "$BACKUP_CORE" || fail 'Cannot back up existing strxcore.'
    MOVED_CORE=1
fi
mv "$STAGED" "$TARGET" || fail 'Cannot install new strxcore.'
NEW_CORE=1

if [ -e "$XRAY_LINK" ] || [ -L "$XRAY_LINK" ]; then
    mv "$XRAY_LINK" "$BACKUP_XRAY" || fail 'Cannot back up existing xray.'
    MOVED_XRAY=1
fi
ln -s strxcore "$XRAY_LINK" || fail 'Cannot create /usr/bin/xray symlink.'
NEW_XRAY=1

# PassWall and PassWall2 must use /usr/bin/xray, NOT /usr/bin/strxcore.
for svc in passwall passwall2; do
    if uci -q get "$svc.@global_app[0]" >/dev/null 2>&1; then
        case "$svc" in
            passwall) UCI_CHANGED_PASSWALL=1 ;;
            passwall2) UCI_CHANGED_PASSWALL2=1 ;;
        esac
        uci set "$svc.@global_app[0].xray_file=$UCI_XRAY_PATH" || fail "Cannot configure $svc."
        uci commit "$svc" || fail "Cannot save $svc."
        echo "$svc -> $UCI_XRAY_PATH"
    else
        echo "INFO: $svc global_app section not found; skipped."
    fi
done

SUCCESS=1
rm -f "$BACKUP_CORE" "$BACKUP_XRAY"
echo 'SUCCESS: Xray core updated.'
"$XRAY_LINK" version 2>/dev/null || "$XRAY_LINK" --version 2>/dev/null || :

# Do not start a service which was previously stopped.
for svc in passwall passwall2; do
    if [ -x "/etc/init.d/$svc" ]; then
        if "/etc/init.d/$svc" status >/dev/null 2>&1; then
            "/etc/init.d/$svc" restart || \
                echo "WARNING: Restart $svc failed; restart it manually." >&2
        else
            echo "INFO: $svc not confirmed running; restart manually if required."
        fi
    fi
done
