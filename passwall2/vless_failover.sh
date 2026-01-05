#!/bin/sh

CONFIG="passwall2"
AS_CONFIG="autoswitch"
LOG_FILE="/var/log/autoswitch.log"
FAIL_LOG="/tmp/vless_fail_count"
CHECK_IP="google.com"

# Fungsi untuk tulis log dengan timestamp
log_msg() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') : $1" >> "$LOG_FILE"
    # Pastikan log tidak terlalu besar (hadkan 100 baris terakhir)
    sed -i ':a;$q;N;101,$D;ba' "$LOG_FILE"
}

# Ambil tetapan dari WebUI
ENABLED=$(uci -q get $AS_CONFIG.@global[0].enabled)
[ "$ENABLED" != "1" ] && exit 0

THRESHOLD=$(uci -q get $AS_CONFIG.@global[0].fail_threshold || echo 3)
MODE=$(uci -q get $AS_CONFIG.@global[0].mode || echo "dynamic_vless")
SPECIFIC_BACKUP=$(uci -q get $AS_CONFIG.@global[0].backup_node)

CURRENT_NODE_ID=$(uci get $CONFIG.@global[0].node)
CURRENT_REMARKS=$(uci get $CONFIG.$CURRENT_NODE_ID.remarks 2>/dev/null || echo "$CURRENT_NODE_ID")

if ping -c 1 -W 3 $CHECK_IP > /dev/null; then
    [ -f $FAIL_LOG ] && [ "$(cat $FAIL_LOG)" != "0" ] && log_msg "Internet OK kembali pada $CURRENT_REMARKS."
    echo 0 > $FAIL_LOG
else
    FAIL_COUNT=$(cat $FAIL_LOG 2>/dev/null || echo 0)
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo $FAIL_COUNT > $FAIL_LOG
    log_msg "Ping Failed!! ($FAIL_COUNT/$THRESHOLD) pada $CURRENT_REMARKS"

    if [ $FAIL_COUNT -ge $THRESHOLD ]; then
        if [ "$MODE" == "specific" ] && [ -n "$SPECIFIC_BACKUP" ]; then
            NEW_NODE_ID="$SPECIFIC_BACKUP"
        else
            VLESS_NODES=$(uci show $CONFIG | grep ".protocol='vless'" | cut -d'.' -f2 | cut -d'=' -f1)
            NEW_NODE_ID=$(echo "$VLESS_NODES" | grep -v "$CURRENT_NODE_ID" | shuf -n 1)
        fi

        if [ -n "$NEW_NODE_ID" ] && [ "$NEW_NODE_ID" != "$CURRENT_NODE_ID" ]; then
            NEW_REMARKS=$(uci get $CONFIG.$NEW_NODE_ID.remarks 2>/dev/null || echo "$NEW_NODE_ID")
            log_msg "FAILOVER: Changing $CURRENT_REMARKS -> $NEW_REMARKS"
            
            uci set $CONFIG.@global[0].node="$NEW_NODE_ID"
            uci commit $CONFIG
            echo 0 > $FAIL_LOG
            /etc/init.d/passwall2 restart > /dev/null 2>&1
        fi
    fi
fi
