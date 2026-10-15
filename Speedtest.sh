#!/bin/sh
# =========================================================
#   SPEED TEST CLI - v10.0 SAFE
#   Kurang agresif • Elak Cloudflare block
# =========================================================

SERVER="https://speed.cloudflare.com"
DURATION=10
DL_CONN=8
UL_CONN=6
DL_CHUNK=5000000    # 5 MB (turun dari 20 MB)
BAR_WIDTH=25

ESC=$(printf '\033')
R="${ESC}[0m"; B="${ESC}[1m"; D="${ESC}[2m"
CY="${ESC}[36m"; GR="${ESC}[32m"; YL="${ESC}[33m"
RD="${ESC}[31m"; BL="${ESC}[34m"; MG="${ESC}[35m"
GY="${ESC}[90m"; WH="${ESC}[97m"
CLR="\r${ESC}[K"

clear 2>/dev/null || printf '\033[2J\033[H'

jget() {
  echo "$1" | tr -d '\n\r' | sed -n "s/.*\"$2\"[ ]*:[ ]*\"\([^\"]*\)\".*/\1/p" | head -1
}

printf "\n"
printf "  ${CY}══════════════════════════════════════════${R}\n"
printf "  ${B}${WH}   SPEED TEST — CLI EDITION  v10.0${R}\n"
printf "  ${D}${GY}   Unlimited • Multi-Thread${R}\n"
printf "  ${CY}══════════════════════════════════════════${R}\n\n"

if ! command -v curl >/dev/null 2>&1; then
  printf "  ${RD}✗ curl tidak dijumpai${R}\n"
  printf "  ${GY}Acode  ${R}: ${CY}apk add curl${R}\n"
  printf "  ${GY}OpenWrt${R}: ${CY}opkg install curl${R}\n\n"
  exit 1
fi

if mkdir -p /tmp 2>/dev/null && touch /tmp/.t_$$ 2>/dev/null; then
  TMP_BASE="/tmp"; rm -f /tmp/.t_$$
else
  TMP_BASE="."
fi

# INFO JARINGAN
printf "  ${B}${BL}◈ INFO JARINGAN${R}\n"
printf "  ${GY}─────────────────────────────────────────${R}\n"

IPINFO=$(curl -s --max-time 10 "http://ip-api.com/json/" 2>/dev/null)
IP_ADDR=$(jget "$IPINFO" "query")
IP_CITY=$(jget "$IPINFO" "city")
IP_CC=$(jget "$IPINFO" "countryCode")
IP_ORG=$(jget "$IPINFO" "isp")
[ -z "$IP_ADDR" ] && IP_ADDR="Unknown"
[ -z "$IP_CITY" ] && IP_CITY="Unknown"
[ -z "$IP_CC" ] && IP_CC="?"
[ -z "$IP_ORG" ] && IP_ORG="Unknown"

case "$IP_CC" in
  MY) IP_COUNTRY="Malaysia" ;;
  SG) IP_COUNTRY="Singapore" ;;
  ID) IP_COUNTRY="Indonesia" ;;
  TH) IP_COUNTRY="Thailand" ;;
  PH) IP_COUNTRY="Philippines" ;;
  VN) IP_COUNTRY="Vietnam" ;;
  JP) IP_COUNTRY="Japan" ;;
  KR) IP_COUNTRY="South Korea" ;;
  IN) IP_COUNTRY="India" ;;
  US) IP_COUNTRY="United States" ;;
  GB) IP_COUNTRY="United Kingdom" ;;
  AU) IP_COUNTRY="Australia" ;;
  *)  IP_COUNTRY="$IP_CC" ;;
esac

printf "  ${GR}✓${R} IP Anda    : ${B}${WH}${IP_ADDR}${R}\n"
printf "  ${GR}✓${R} Lokasi     : ${B}${WH}${IP_CITY}, ${IP_COUNTRY}${R}\n"
printf "  ${GR}✓${R} ISP        : ${B}${WH}${IP_ORG}${R}\n"

NF_LOC=$(echo "$IP_CC" | tr 'A-Z' 'a-z')
case "$NF_LOC" in
  my) NF_NAME="Malaysia" ;;
  sg) NF_NAME="Singapore" ;;
  id) NF_NAME="Indonesia" ;;
  th) NF_NAME="Thailand" ;;
  ph) NF_NAME="Philippines" ;;
  vn) NF_NAME="Vietnam" ;;
  jp) NF_NAME="Japan" ;;
  kr) NF_NAME="South Korea" ;;
  in) NF_NAME="India" ;;
  us) NF_NAME="United States" ;;
  gb) NF_NAME="United Kingdom" ;;
  au) NF_NAME="Australia" ;;
  ca) NF_NAME="Canada" ;;
  hk) NF_NAME="Hong Kong" ;;
  tw) NF_NAME="Taiwan" ;;
  *)  NF_NAME="Unknown" ;;
esac
printf "  ${GR}✓${R} Netflix    : ${B}${MG}${NF_NAME} (${NF_LOC})${R}\n\n"

# PING TEST
printf "  ${B}${BL}◈ PING TEST${R}\n"
printf "  ${GY}─────────────────────────────────────────${R}\n"

PING_MIN=99999
PING_AVG=0
PING_MODE="HTTP"

if command -v ping >/dev/null 2>&1; then
  PING_RESULT=$(ping -c 5 -W 3 speed.cloudflare.com 2>/dev/null | grep -E "min/avg|rtt")
  if [ -n "$PING_RESULT" ]; then
    PING_MIN=$(echo "$PING_RESULT" | sed 's/.*= //' | cut -d'/' -f1 | cut -d'.' -f1)
    PING_AVG=$(echo "$PING_RESULT" | sed 's/.*= //' | cut -d'/' -f2 | cut -d'.' -f1)
    PING_MODE="ICMP"
  fi
fi

if [ "$PING_MODE" != "ICMP" ]; then
  PING_MIN=99999
  PING_SUM=0
  i=0
  while [ $i -lt 5 ]; do
    T=$(curl -s -o /dev/null --max-time 5 -w "%{time_total}" \
      "${SERVER}/__down?bytes=0&r=$RANDOM" 2>/dev/null)
    MS=$(awk "BEGIN { printf \"%.0f\", $T * 1000 }")
    PING_SUM=$((PING_SUM + MS))
    [ "$MS" -lt "$PING_MIN" ] && PING_MIN=$MS
    i=$((i + 1))
  done
  PING_AVG=$((PING_SUM / 5))
fi

printf "  ${GR}✓${R} Ping       : ${B}${YL}${PING_MIN} ms${R} ${D}(min)${R} ${GY}/ ${PING_AVG} ms (avg)${R} ${D}[${PING_MODE}]${R}\n\n"

# DOWNLOAD TEST
printf "  ${B}${BL}◈ DOWNLOAD TEST${R}\n"
printf "  ${GY}─────────────────────────────────────────${R}\n"
printf "  ${D}${DL_CONN} sambungan, ${DURATION}s, chunk 5MB${R}\n\n"

TMP="${TMP_BASE}/st_dl_$$"
mkdir -p "$TMP"
START=$(date +%s)

i=1
while [ $i -le $DL_CONN ]; do
  (
    while true; do
      [ $(( $(date +%s) - START )) -ge $DURATION ] && break
      S=$(curl -s -o /dev/null -w "%{size_download}" --max-time 6 \
        "${SERVER}/__down?bytes=${DL_CHUNK}&r=$RANDOM" 2>/dev/null)
      [ -z "$S" ] && S=0
      echo "$S" >> "${TMP}/dl_$i"
    done
  ) &
  i=$((i + 1))
done

LAST_TOTAL=0
LAST_TIME=$START
SPD=0

while true; do
  NOW=$(date +%s)
  EL=$((NOW - START))
  [ "$EL" -ge "$DURATION" ] && break

  TOTAL=0
  i=1
  while [ $i -le $DL_CONN ]; do
    if [ -f "${TMP}/dl_$i" ]; then
      S=$(awk '{s+=$1} END {print s+0}' "${TMP}/dl_$i" 2>/dev/null)
      [ -z "$S" ] && S=0
      TOTAL=$((TOTAL + S))
    fi
    i=$((i + 1))
  done

  DT=$((NOW - LAST_TIME))
  if [ "$DT" -gt 0 ]; then
    DELTA=$((TOTAL - LAST_TOTAL))
    SPD=$(awk "BEGIN { printf \"%.1f\", ($DELTA * 8) / ($DT * 1000000) }")
    LAST_TOTAL=$TOTAL
    LAST_TIME=$NOW
  fi

  PCT=$((EL * 100 / DURATION))
  FILL=$((PCT * BAR_WIDTH / 100))
  EMPTY=$((BAR_WIDTH - FILL))
  BAR=""
  j=0; while [ $j -lt $FILL ]; do BAR="${BAR}█"; j=$((j + 1)); done
  j=0; while [ $j -lt $EMPTY ]; do BAR="${BAR}░"; j=$((j + 1)); done

  printf "${CLR}  ${CY}[${BAR}]${R}  ${B}${WH}%8s${R} ${GY}Mbps${R}  ${D}%2ss${R}" \
    "$SPD" "$EL"
  sleep 1
done
wait

TOTAL=0
i=1
while [ $i -le $DL_CONN ]; do
  if [ -f "${TMP}/dl_$i" ]; then
    S=$(awk '{s+=$1} END {print s+0}' "${TMP}/dl_$i" 2>/dev/null)
    [ -z "$S" ] && S=0
    TOTAL=$((TOTAL + S))
  fi
  i=$((i + 1))
done

END=$(date +%s)
DUR=$((END - START))
[ "$DUR" -eq 0 ] && DUR=1
DL=$(awk "BEGIN { printf \"%.1f\", ($TOTAL * 8) / ($DUR * 1000000) }")
DL_MB=$(awk "BEGIN { printf \"%.1f\", $TOTAL / 1048576 }")

printf "${CLR}  ${GR}✓${R} Download   : ${B}${CY}${DL} Mbps${R}  ${D}(${DL_MB} MB)${R}\n\n"
rm -rf "$TMP"

# UPLOAD TEST
printf "  ${B}${BL}◈ UPLOAD TEST${R}\n"
printf "  ${GY}─────────────────────────────────────────${R}\n"
printf "  ${D}${UL_CONN} sambungan, ${DURATION}s${R}\n\n"

TMP="${TMP_BASE}/st_ul_$$"
mkdir -p "$TMP"
dd if=/dev/urandom of="${TMP}/chunk" bs=1024 count=1024 2>/dev/null
START=$(date +%s)

i=1
while [ $i -le $UL_CONN ]; do
  (
    END_T=$((START + DURATION))
    while [ "$(date +%s)" -lt "$END_T" ]; do
      S=$(curl -s --max-time 3 -X POST \
        -H "Content-Type: application/octet-stream" \
        --data-binary "@${TMP}/chunk" \
        -o /dev/null -w "%{size_upload}" \
        "${SERVER}/__up" 2>/dev/null)
      [ -z "$S" ] && S=0
      echo "$S" >> "${TMP}/ul_$i"
    done
  ) &
  i=$((i + 1))
done

LAST_TOTAL=0
LAST_TIME=$START
SPD=0

while true; do
  NOW=$(date +%s)
  EL=$((NOW - START))
  [ "$EL" -ge "$DURATION" ] && break

  TOTAL=0
  i=1
  while [ $i -le $UL_CONN ]; do
    if [ -f "${TMP}/ul_$i" ]; then
      S=$(awk '{s+=$1} END {print s+0}' "${TMP}/ul_$i" 2>/dev/null)
      [ -z "$S" ] && S=0
      TOTAL=$((TOTAL + S))
    fi
    i=$((i + 1))
  done

  DT=$((NOW - LAST_TIME))
  if [ "$DT" -gt 0 ]; then
    DELTA=$((TOTAL - LAST_TOTAL))
    SPD=$(awk "BEGIN { printf \"%.1f\", ($DELTA * 8) / ($DT * 1000000) }")
    LAST_TOTAL=$TOTAL
    LAST_TIME=$NOW
  fi

  PCT=$((EL * 100 / DURATION))
  FILL=$((PCT * BAR_WIDTH / 100))
  EMPTY=$((BAR_WIDTH - FILL))
  BAR=""
  j=0; while [ $j -lt $FILL ]; do BAR="${BAR}█"; j=$((j + 1)); done
  j=0; while [ $j -lt $EMPTY ]; do BAR="${BAR}░"; j=$((j + 1)); done

  printf "${CLR}  ${MG}[${BAR}]${R}  ${B}${WH}%8s${R} ${GY}Mbps${R}  ${D}%2ss${R}" \
    "$SPD" "$EL"
  sleep 1
done
wait

TOTAL=0
i=1
while [ $i -le $UL_CONN ]; do
  if [ -f "${TMP}/ul_$i" ]; then
    S=$(awk '{s+=$1} END {print s+0}' "${TMP}/ul_$i" 2>/dev/null)
    [ -z "$S" ] && S=0
    TOTAL=$((TOTAL + S))
  fi
  i=$((i + 1))
done

END=$(date +%s)
DUR=$((END - START))
[ "$DUR" -eq 0 ] && DUR=1
UL=$(awk "BEGIN { printf \"%.1f\", ($TOTAL * 8) / ($DUR * 1000000) }")
UL_MB=$(awk "BEGIN { printf \"%.1f\", $TOTAL / 1048576 }")

printf "${CLR}  ${GR}✓${R} Upload     : ${B}${GR}${UL} Mbps${R}  ${D}(${UL_MB} MB)${R}\n\n"
rm -rf "$TMP"

# HASIL AKHIR
printf "  ${CY}══════════════════════════════════════════${R}\n"
printf "  ${B}${WH}   HASIL AKHIR${R}\n"
printf "  ${CY}══════════════════════════════════════════${R}\n"
printf "     ${GY}Ping       ${R}  ${B}${YL}%s ms${R}\n" "$PING_MIN"
printf "     ${GY}Download   ${R}  ${B}${CY}%s Mbps${R}\n" "$DL"
printf "     ${GY}Upload     ${R}  ${B}${GR}%s Mbps${R}\n" "$UL"
printf "  ${CY}══════════════════════════════════════════${R}\n\n"

# YOUTUBE
printf "  ${B}${RD}▶ YOUTUBE QUALITY${R}\n"
printf "  ${GY}─────────────────────────────────────────${R}\n"

chk() {
  L="$1"; N="$2"
  OK=$(awk "BEGIN { print ($DL >= $N) ? 1 : 0 }")
  if [ "$OK" = "1" ]; then
    printf "  ${GR}●${R} ${B}%-7s${R} ${GY}%6s Mbps${R}   ${GR}✓${R}\n" "$L" "$N"
  else
    printf "  ${RD}○${R} ${B}%-7s${R} ${GY}%6s Mbps${R}   ${RD}✗${R}\n" "$L" "$N"
  fi
}

chk "144p"  0.1
chk "240p"  0.3
chk "360p"  1
chk "480p"  2.5
chk "720p"  5
chk "1080p" 8
chk "2K"    16
chk "4K"    35
printf "\n"

BEST="Tidak cukup"
awk "BEGIN { exit !($DL >= 35) }" && BEST="4K (2160p)"
awk "BEGIN { exit !($DL >= 16 && $DL < 35) }" && BEST="2K (1440p)"
awk "BEGIN { exit !($DL >= 8 && $DL < 16) }" && BEST="1080p (FHD)"
awk "BEGIN { exit !($DL >= 5 && $DL < 8) }" && BEST="720p (HD)"
awk "BEGIN { exit !($DL >= 2.5 && $DL < 5) }" && BEST="480p"
awk "BEGIN { exit !($DL >= 1 && $DL < 2.5) }" && BEST="360p"
awk "BEGIN { exit !($DL >= 0.3 && $DL < 1) }" && BEST="240p"
awk "BEGIN { exit !($DL >= 0.1 && $DL < 0.3) }" && BEST="144p"

printf "  ${B}${WH}Kualiti tertinggi :${R}  ${B}${RD}▶ ${BEST}${R}\n\n"

# RINGKASAN
printf "  ${CY}══════════════════════════════════════════${R}\n"
printf "  ${B}${WH}   RINGKASAN${R}\n"
printf "  ${CY}══════════════════════════════════════════${R}\n"
printf "  ${GY}IP        :${R} ${WH}%s${R}\n" "$IP_ADDR"
printf "  ${GY}Lokasi    :${R} ${WH}%s, %s${R}\n" "$IP_CITY" "$IP_COUNTRY"
printf "  ${GY}ISP       :${R} ${WH}%s${R}\n" "$IP_ORG"
printf "  ${GY}Netflix   :${R} ${MG}%s (%s)${R}\n" "$NF_NAME" "$NF_LOC"
printf "  ${CY}══════════════════════════════════════════${R}\n\n"

LOG="${TMP_BASE}/speedtest.log"
{
  echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
  echo "IP        : $IP_ADDR"
  echo "Lokasi    : $IP_CITY, $IP_COUNTRY"
  echo "ISP       : $IP_ORG"
  echo "Netflix   : $NF_NAME ($NF_LOC)"
  echo "Ping      : $PING_MIN ms [$PING_MODE]"
  echo "Download  : $DL Mbps"
  echo "Upload    : $UL Mbps"
  echo "YouTube   : $BEST"
  echo ""
} >> "$LOG" 2>/dev/null

printf "  ${D}${GY}Log: ${LOG}${R}\n\n"