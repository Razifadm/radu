#!/bin/sh
# install-hermes-bpi-r3-v2.sh
#
# Hermes Agent host installer for:
#   Banana Pi BPI-R3 Mini
#   ImmortalWrt / OpenWrt (musl, aarch64)
#
# Key compatibility choices:
#   - DOES NOT run opkg update or upgrade packages.
#   - DOES NOT require curl.
#   - DOES NOT require git/git-http.
#   - Downloads with uclient-fetch / wget first.
#   - Uses BusyBox-compatible tar flags only.
#   - Installs official uv aarch64-musl binary.
#   - Uses uv-managed CPython 3.11 (musl aarch64 supported).
#   - Keeps heavy runtime/data on external storage.
#   - Installs Hermes from GitHub source tarball instead of git clone.
#   - Keeps venv OUTSIDE source tree so source updates are safe.
#   - Provides OpenWrt procd gateway service, disabled by default.
#
# Default storage:
#   /mnt/powerbolehlaa/hermes
#
# Usage:
#   sh install-hermes-bpi-r3-v2.sh
#
# Overrides:
#   HERMES_BASE=/mnt/sda1/hermes
#   HERMES_BRANCH=main
#   HERMES_INSTALL_PROFILE=host   # core | host | full
#   HERMES_SETUP=1                # 1 runs setup wizard when interactive
#   HERMES_UV_VERSION=0.12.17

set -eu
umask 022

BASE="${HERMES_BASE:-/mnt/powerbolehlaa/hermes}"
BRANCH="${HERMES_BRANCH:-main}"
PROFILE="${HERMES_INSTALL_PROFILE:-host}"
RUN_SETUP="${HERMES_SETUP:-1}"
UV_VERSION="${HERMES_UV_VERSION:-0.12.17}"

APP="$BASE/hermes-agent"
DATA="$BASE/data"
PYTHON_ROOT="$BASE/python"
CACHE="$BASE/cache/uv"
TMPROOT="$BASE/tmp"
VENV="$BASE/venv"

UV="$DATA/bin/uv"
LAUNCHER="/usr/local/bin/hermes"
UPDATE_HELPER="/usr/local/sbin/hermes-bpi-update"
SERVICE_RUNNER="$BASE/hermes-gateway-run.sh"
SERVICE="/etc/init.d/hermes-gateway"

PYTHON_VERSION="3.11"
UV_TARGET="aarch64-unknown-linux-musl"

say()  { printf '\033[1;36m[HERMES-BPI]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*" >&2; exit 1; }

need_root() {
    [ "$(id -u 2>/dev/null || echo 1)" = "0" ] || die "Run this installer as root."
}

detect_platform() {
    arch="$(uname -m)"
    case "$arch" in
        aarch64|arm64) ;;
        *) die "Unsupported architecture: $arch. This build targets BPI-R3 Mini aarch64." ;;
    esac

    if ls /lib/ld-musl-*.so.1 >/dev/null 2>&1; then
        ok "musl libc detected."
    else
        warn "musl loader not detected. Continuing, but this installer is intended for ImmortalWrt/OpenWrt musl."
    fi
}

prepare_storage() {
    mkdir -p "$BASE" "$DATA/bin" "$PYTHON_ROOT" "$CACHE" "$TMPROOT"
    chmod 700 "$DATA" 2>/dev/null || true

    export HERMES_HOME="$DATA"
    export UV_PYTHON_INSTALL_DIR="$PYTHON_ROOT"
    export UV_CACHE_DIR="$CACHE"
    export UV_LINK_MODE=copy
    export TMPDIR="$TMPROOT"
    export HOME="${HOME:-/root}"

    # Avoid filling the router RAM-backed /tmp.
    ok "Runtime storage: $BASE"

    # Git is no longer required, but Python virtualenvs still prefer a Unix FS.
    t="$BASE/.hermes-fs-test.$$"
    l="$BASE/.hermes-fs-link.$$"
    : > "$t"
    if ln -s "$(basename "$t")" "$l" 2>/dev/null; then
        rm -f "$l" "$t"
    else
        rm -f "$t"
        warn "Filesystem at $BASE does not support symlinks."
        warn "Use ext4/f2fs/btrfs if possible; exFAT/FAT may break Python virtualenvs."
    fi

    free_kb="$(df -Pk "$BASE" 2>/dev/null | awk 'NR==2 {print $4}' | tail -n1)"
    case "$free_kb" in
        ''|*[!0-9]*) ;;
        *)
            if [ "$free_kb" -lt 1048576 ]; then
                warn "Less than 1 GiB free under $BASE."
            fi
            ;;
    esac
}

fetch_file() {
    url="$1"
    out="$2"

    rm -f "$out"
    mkdir -p "$(dirname "$out")"

    # OpenWrt-native downloader first. It avoids the currently broken curl/libcurl pair.
    if command -v uclient-fetch >/dev/null 2>&1; then
        say "Download via uclient-fetch: $url"
        if uclient-fetch -q -O "$out" "$url" && [ -s "$out" ]; then
            return 0
        fi
        rm -f "$out"
    fi

    # BusyBox wget or standalone wget.
    if command -v wget >/dev/null 2>&1; then
        say "Download via wget: $url"
        if wget -q -O "$out" "$url" && [ -s "$out" ]; then
            return 0
        fi
        rm -f "$out"
    fi

    # curl is LAST because the user's current /usr/bin/curl has a libcurl ABI mismatch.
    if command -v curl >/dev/null 2>&1; then
        if curl --version >/dev/null 2>&1; then
            say "Download via curl: $url"
            if curl -fL --retry 3 --connect-timeout 20 "$url" -o "$out" && [ -s "$out" ]; then
                return 0
            fi
            rm -f "$out"
        else
            warn "curl exists but cannot execute; skipping it."
        fi
    fi

    die "No working HTTPS downloader found. Need working uclient-fetch or wget."
}

install_uv() {
    if [ -x "$UV" ] && "$UV" --version >/dev/null 2>&1; then
        ok "uv already available: $("$UV" --version)"
        return 0
    fi

    say "Installing uv $UV_VERSION for aarch64 musl..."

    work="$TMPROOT/uv-install.$$"
    archive="$work/uv.tar.gz"
    rm -rf "$work"
    mkdir -p "$work"

    url="https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-${UV_TARGET}.tar.gz"
    fetch_file "$url" "$archive"

    # BusyBox-safe extraction. Do not use GNU tar long options.
    tar -xzf "$archive" -C "$work" || die "Failed to extract uv archive."

    uv_src="$(find "$work" -type f -name uv 2>/dev/null | head -n1)"
    [ -n "$uv_src" ] || die "uv binary not found after extraction."

    cp "$uv_src" "$UV"
    chmod 755 "$UV"
    rm -rf "$work"

    "$UV" --version >/dev/null 2>&1 || die "Installed uv binary does not execute."
    ok "Installed $("$UV" --version)"
}

download_hermes_source() {
    say "Downloading Hermes source branch: $BRANCH"

    work="$TMPROOT/hermes-source.$$"
    archive="$work/hermes.tar.gz"
    stage="$work/stage"

    rm -rf "$work"
    mkdir -p "$stage"

    # codeload avoids git/git-http/libcurl entirely.
    url="https://codeload.github.com/NousResearch/hermes-agent/tar.gz/refs/heads/${BRANCH}"
    fetch_file "$url" "$archive"

    tar -xzf "$archive" -C "$stage" || die "Failed to extract Hermes source archive."

    src="$(find "$stage" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n1)"
    [ -n "$src" ] || die "Unable to locate extracted Hermes source directory."
    [ -f "$src/pyproject.toml" ] || die "Extracted source is missing pyproject.toml."

    old="$BASE/.hermes-agent.old"
    rm -rf "$old"

    if [ -d "$APP" ]; then
        mv "$APP" "$old"
    fi

    if mv "$src" "$APP"; then
        rm -rf "$old" "$work"
    else
        rm -rf "$APP"
        [ -d "$old" ] && mv "$old" "$APP" || true
        die "Failed to install Hermes source tree."
    fi

    ok "Hermes source ready: $APP"
}

install_python() {
    say "Installing uv-managed Python $PYTHON_VERSION..."

    "$UV" python install "$PYTHON_VERSION" \
        || die "uv failed to install Python $PYTHON_VERSION."

    if [ ! -x "$VENV/bin/python" ]; then
        say "Creating persistent Hermes virtualenv: $VENV"
        rm -rf "$VENV"
        "$UV" venv "$VENV" --python "$PYTHON_VERSION" \
            || die "Failed to create Hermes virtualenv."
    fi

    "$VENV/bin/python" -c 'import sys; assert (3,11) <= sys.version_info[:2] < (3,14)' \
        || die "Installed Python version is outside Hermes supported range."

    ok "Python: $("$VENV/bin/python" --version 2>&1)"
}

install_hermes_deps() {
    case "$PROFILE" in
        core)
            spec="."
            ;;
        host)
            # Base Hermes already contains FastAPI/Uvicorn pieces.
            # [web,pty] keeps dashboard/headless-server support without [all].
            spec=".[web,pty]"
            ;;
        full)
            spec=".[all]"
            ;;
        *)
            die "Unknown HERMES_INSTALL_PROFILE='$PROFILE'. Use core, host, or full."
            ;;
    esac

    say "Installing Hermes profile: $PROFILE ($spec)"

    (
        cd "$APP"
        "$UV" pip install \
            --python "$VENV/bin/python" \
            -e "$spec"
    ) || die "Hermes dependency installation failed."

    # Archive-based local compatibility install. Do not pretend there is a .git checkout.
    printf '%s\n' unknown > "$APP/.install_method"

    ok "Hermes package installed."
}

prepare_data() {
    say "Preparing Hermes data directory..."

    for d in cron sessions logs pairing hooks image_cache audio_cache memories skills profiles; do
        mkdir -p "$DATA/$d"
    done

    if [ ! -f "$DATA/.env" ]; then
        if [ -f "$APP/.env.example" ]; then
            cp "$APP/.env.example" "$DATA/.env"
        else
            : > "$DATA/.env"
        fi
    fi
    chmod 600 "$DATA/.env" 2>/dev/null || true

    if [ ! -f "$DATA/config.yaml" ] && [ -f "$APP/cli-config.yaml.example" ]; then
        cp "$APP/cli-config.yaml.example" "$DATA/config.yaml"
    fi

    ok "HERMES_HOME: $DATA"
}

write_update_helper() {
    mkdir -p "$(dirname "$UPDATE_HELPER")"

    cat > "$UPDATE_HELPER" <<EOF
#!/bin/sh
set -eu

BASE='$BASE'
APP='$APP'
DATA='$DATA'
PYTHON_ROOT='$PYTHON_ROOT'
CACHE='$CACHE'
TMPROOT='$TMPROOT'
VENV='$VENV'
UV='$UV'
BRANCH='$BRANCH'
PROFILE='$PROFILE'

export HERMES_HOME="\$DATA"
export UV_PYTHON_INSTALL_DIR="\$PYTHON_ROOT"
export UV_CACHE_DIR="\$CACHE"
export UV_LINK_MODE=copy
export TMPDIR="\$TMPROOT"

fetch_file() {
    url="\$1"
    out="\$2"
    rm -f "\$out"

    if command -v uclient-fetch >/dev/null 2>&1; then
        if uclient-fetch -q -O "\$out" "\$url" && [ -s "\$out" ]; then
            return 0
        fi
        rm -f "\$out"
    fi

    if command -v wget >/dev/null 2>&1; then
        if wget -q -O "\$out" "\$url" && [ -s "\$out" ]; then
            return 0
        fi
        rm -f "\$out"
    fi

    if command -v curl >/dev/null 2>&1 && curl --version >/dev/null 2>&1; then
        curl -fL --retry 3 "\$url" -o "\$out" && [ -s "\$out" ] && return 0
        rm -f "\$out"
    fi

    echo "[FAIL] No working downloader." >&2
    exit 1
}

echo "[HERMES-BPI] Updating Hermes archive from branch \$BRANCH ..."

work="\$TMPROOT/hermes-update.\$\$"
archive="\$work/hermes.tar.gz"
stage="\$work/stage"
old="\$BASE/.hermes-agent.old"

rm -rf "\$work" "\$old"
mkdir -p "\$stage"

fetch_file "https://codeload.github.com/NousResearch/hermes-agent/tar.gz/refs/heads/\${BRANCH}" "\$archive"
tar -xzf "\$archive" -C "\$stage"

src="\$(find "\$stage" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n1)"
[ -n "\$src" ] && [ -f "\$src/pyproject.toml" ] || {
    echo "[FAIL] Invalid Hermes source archive." >&2
    exit 1
}

[ -d "\$APP" ] && mv "\$APP" "\$old"
if ! mv "\$src" "\$APP"; then
    rm -rf "\$APP"
    [ -d "\$old" ] && mv "\$old" "\$APP" || true
    echo "[FAIL] Source update failed; previous source restored." >&2
    exit 1
fi

rm -rf "\$old" "\$work"

"\$UV" python install '$PYTHON_VERSION'

if [ ! -x "\$VENV/bin/python" ]; then
    "\$UV" venv "\$VENV" --python '$PYTHON_VERSION'
fi

case "\$PROFILE" in
    core) spec='.' ;;
    host) spec='.[web,pty]' ;;
    full) spec='.[all]' ;;
    *) echo "[FAIL] Unknown profile: \$PROFILE" >&2; exit 1 ;;
esac

cd "\$APP"
"\$UV" pip install --python "\$VENV/bin/python" -e "\$spec"
printf '%s\n' unknown > "\$APP/.install_method"

"\$VENV/bin/python" "\$APP/hermes" --help >/dev/null
echo "[ OK ] Hermes update complete."
EOF

    chmod 755 "$UPDATE_HELPER"
}

write_launcher() {
    mkdir -p /usr/local/bin

    cat > "$LAUNCHER" <<EOF
#!/bin/sh
export HERMES_HOME='$DATA'
export UV_PYTHON_INSTALL_DIR='$PYTHON_ROOT'
export UV_CACHE_DIR='$CACHE'
export UV_LINK_MODE=copy
export TMPDIR='$TMPROOT'
unset PYTHONPATH
unset PYTHONHOME

# Because this installation intentionally has no .git checkout,
# route updates through our archive-based OpenWrt updater.
if [ "\${1:-}" = "update" ]; then
    shift
    exec '$UPDATE_HELPER' "\$@"
fi

exec '$VENV/bin/python' '$APP/hermes' "\$@"
EOF

    chmod 755 "$LAUNCHER"
    ln -sf "$LAUNCHER" /usr/bin/hermes

    ok "Installed command: /usr/bin/hermes"
}

write_gateway_service() {
    cat > "$SERVICE_RUNNER" <<EOF
#!/bin/sh

# External storage may mount after procd starts.
i=0
while [ ! -x '$VENV/bin/python' ] && [ "\$i" -lt 60 ]; do
    i=\$((i + 1))
    sleep 2
done

[ -x '$VENV/bin/python' ] || {
    logger -t hermes-gateway "Hermes runtime unavailable: $VENV"
    exit 1
}

exec '$LAUNCHER' gateway run
EOF
    chmod 755 "$SERVICE_RUNNER"

    if [ -d /etc/init.d ] && [ -x /sbin/procd ]; then
        cat > "$SERVICE" <<EOF
#!/bin/sh /etc/rc.common
USE_PROCD=1
START=95
STOP=10

start_service() {
    procd_open_instance
    procd_set_param command '$SERVICE_RUNNER'
    procd_set_param respawn 3600 5 5
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}
EOF
        chmod 755 "$SERVICE"
        ok "Installed procd service: $SERVICE (disabled by default)"
    else
        warn "procd not found; gateway init service was not installed."
    fi
}

verify() {
    say "Running Hermes smoke test..."

    "$LAUNCHER" --help >/dev/null 2>&1 \
        || die "Hermes CLI smoke test failed."

    ok "Hermes CLI starts."

    printf '\n'
    printf '%s\n' "============================================================"
    printf '%s\n' " Hermes Agent - BPI-R3 Mini / ImmortalWrt"
    printf '%s\n' "============================================================"
    printf ' Base       : %s\n' "$BASE"
    printf ' Source     : %s\n' "$APP"
    printf ' Data       : %s\n' "$DATA"
    printf ' Venv       : %s\n' "$VENV"
    printf ' Python     : %s\n' "$PYTHON_ROOT"
    printf ' uv         : %s\n' "$UV"
    printf ' Profile    : %s\n' "$PROFILE"
    printf ' CLI        : hermes\n'
    printf ' Update     : hermes update\n'
    printf '%s\n' "============================================================"
}

maybe_setup() {
    if [ "$RUN_SETUP" != "1" ]; then
        say "Setup skipped. Run later: hermes setup"
        return 0
    fi

    if [ -t 0 ]; then
        printf '\n'
        say "Launching Hermes setup wizard..."
        "$LAUNCHER" setup \
            || warn "Setup did not finish. Run again later: hermes setup"
    else
        say "Non-interactive session. Run later: hermes setup"
    fi
}

main() {
    need_root
    detect_platform
    prepare_storage

    # IMPORTANT: deliberately no "opkg update" and no package upgrades here.
    # The router firmware/package feed versions must remain coherent.
    command -v tar >/dev/null 2>&1 || die "tar is missing."
    command -v find >/dev/null 2>&1 || die "find is missing."

    if command -v uclient-fetch >/dev/null 2>&1; then
        ok "Downloader available: uclient-fetch"
    elif command -v wget >/dev/null 2>&1; then
        ok "Downloader available: wget"
    else
        warn "Neither uclient-fetch nor wget found. curl will be attempted only if it runs."
    fi

    install_uv
    download_hermes_source
    install_python
    install_hermes_deps
    prepare_data
    write_update_helper
    write_launcher
    write_gateway_service
    verify
    maybe_setup

    printf '\n'
    say "Useful commands:"
    printf '  hermes setup\n'
    printf '  hermes doctor\n'
    printf '  hermes chat\n'
    printf '  hermes dashboard\n'
    printf '  hermes gateway run\n'
    printf '  hermes update\n'
    if [ -f "$SERVICE" ]; then
        printf '  /etc/init.d/hermes-gateway enable\n'
        printf '  /etc/init.d/hermes-gateway start\n'
        printf '  logread -e hermes\n'
    fi
}

main "$@"
