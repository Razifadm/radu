cat > /usr/bin/Speedtest << 'ENDOFSCRIPT'
#!/bin/sh
# =========================================================
#   SPEED TEST CLI - OOKLA EDITION
#   Auto-download Ookla CLI kalau belum ada
# =========================================================

OOKLA_BIN="/usr/bin/speedtest"
BAR_WIDTH=28

ESC=$(printf '\033')
R="${ESC}[0m"; B="${ESC}[1m"; D="${ESC}[2m"
CY="${ESC}[36m"; GR="${ESC}[32m"; YL="${ESC}[33m"
RD="${ESC}[31m"; BL="${ESC}[34m"; MG="${ESC}[35m"
GY="${ESC}[90m"; WH="${ESC}[97m"
CLR="\r${ESC}[K"

clear 2>/dev/null || printf '\033[2J\033[H'

printf "\n"
printf "  ${CY}══════════════════════════════════════════${R}\n"
printf "  ${B}${WH}   SPEED TEST — OOKLA EDITION${R}\n"
printf "  ${CY}══════════════════════════════════════════${R}\n\n"

# AUTO-INSTALL OOKLA CLI
if [ ! -x "$OOKLA_BIN" ]; then
  printf "  ${YL}⚠ Ookla CLI tidak dijumpai. Memasang...${R}\n\n"

  ARCH=$(uname -m)
  case "$ARCH" in
    aarch64) OOKLA_ARCH="aarch64" ;;
    armv7l|armv6l) OOKLA_ARCH="armhf" ;;
    x86_64) OOKLA_ARCH="x86_64" ;;
    mips) OOKLA_ARCH="mips" ;;
    mipsel) OOKLA_ARCH="mipsel" ;;
    *) OOKLA_ARCH="aarch64" ;;
  esac

  printf "  ${GY}Architecture : ${WH}${ARCH}${R}\n"
  printf "  ${GY}Download     : ${WH}linux-${OOKLA_ARCH}${R}\n\n"

  if ! command -v wget >/dev/null 2>&1 && ! command -v uclient-fetch >/dev/null 2>&1; then
    printf "  ${YL}Memasang wget-ssl...${R}\n"
    opkg update >/dev/null 2>&1
    opkg install wget-ssl >/dev/null 2>&1
  fi

  cd /tmp || exit 1
  URL="https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-${OOKLA_ARCH}.tgz"

  printf "  ${GY}Downloading...${R}"
  if command -v wget >/dev/null 2>&1; then
    wget -q "$URL" -O ookla.tgz 2>/dev/null
  else
    uclient-fetch -qO ookla.tgz "$URL" 2>/dev/null
  fi

  if [ ! -s /tmp/ookla.tgz ]; then
    printf "\r  ${RD}✗ Gagal download Ookla CLI${R}\n"
    exit 1
  fi

  printf "\r  ${GY}Extracting...${R}                    "
  tar -xzf ookla.tgz 2>/dev/null
  chmod +x speedtest 2>/dev/null
  mv speedtest "$OOKLA_BIN" 2>/dev/null
  rm -f ookla.tgz

  if [ ! -x "$OOKLA_BIN" ]; then
    printf "\r  ${RD}✗ Gagal install Ookla CLI${R}                    \n\n"
    exit 1
  fi

  printf "\r  ${GR}✓ Ookla CLI dipasang!${R}                    \n\n"
fi

if mkdir -p /tmp 2>/dev/null && touch /tmp/.t_$$ 2>/dev/null; then
  TMP_BASE="/tmp"; rm -f /tmp/.t_$$
else
  TMP_BASE="."
fi

# Ambil IP & Country code
IP_ADDR=$(uclient-fetch -qO- --timeout=8 "http://ip-api.com/line/?fields=query" 2>/dev/null | tr -d ' \n\r')
IP_CC=$(uclient-fetch -qO- --timeout=8 "http://ip-api.com/line/?fields=countryCode" 2>/dev/null | tr -d ' \n\r')

[ -z "$IP_ADDR" ] && IP_ADDR="Unknown"
[ -z "$IP_CC" ] && IP_CC="?"
[ "$IP_CC" = "null" ] && IP_CC="?"

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

printf "  ${B}${BL}◈ SPEEDTEST (Speedtest.net)${R}\n"
printf "  ${GY}─────────────────────────────────────────${R}\n"

OOKLA_JSON="${TMP_BASE}/ookla_$$.json"

"$OOKLA_BIN" --accept-license --accept-gdpr -f json > "$OOKLA_JSON" 2>/dev/null &
OOKLA_PID=$!

START=$(date +%s)
PHASE="Menyambung..."

while kill -0 $OOKLA_PID 2>/dev/null; do
  NOW=$(date +%s)
  EL=$((NOW - START))

  if [ $EL -lt 6 ]; then
    PHASE="Mencari server..."
  elif [ $EL -lt 12 ]; then
    PHASE="Mengukur ping..."
  elif [ $EL -lt 30 ]; then
    PHASE="Mengukur download..."
  elif [ $EL -lt 45 ]; then
    PHASE="Mengukur upload..."
  else
    PHASE="Menyelesaikan..."
  fi

  PCT=$((EL * 100 / 50))
  [ "$PCT" -gt 95 ] && PCT=95
  FILL=$((PCT * BAR_WIDTH / 100))
  EMPTY=$((BAR_WIDTH - FILL))

  BAR=""
  j=0; while [ $j -lt $FILL ]; do BAR="${BAR}█"; j=$((j + 1)); done
  j=0; while [ $j -lt $EMPTY ]; do BAR="${BAR}░"; j=$((j + 1)); done

  printf "${CLR}  ${CY}[${BAR}]${R}  ${B}${WH}%-22s${R}  ${GY}%2ss${R}" \
    "$PHASE" "$EL"
  sleep 1
done
wait $OOKLA_PID 2>/dev/null

printf "${ESC}[2K\r"

if [ ! -s "$OOKLA_JSON" ]; then
  printf "  ${RD}✗ Gagal dapat keputusan dari Ookla${R}\n"
  rm -f "$OOKLA_JSON"
  exit 1
fi

RESULT=$(cat "$OOKLA_JSON")
rm -f "$OOKLA_JSON"

PING=$(echo "$RESULT" | grep -o '"latency":[0-9.]*' | head -1 | cut -d':' -f2)
PING_JITTER=$(echo "$RESULT" | grep -o '"jitter":[0-9.]*' | head -1 | cut -d':' -f2)
DL_BW=$(echo "$RESULT" | grep -o '"bandwidth":[0-9]*' | head -1 | cut -d':' -f2)
UL_BW=$(echo "$RESULT" | grep -o '"bandwidth":[0-9]*' | tail -1 | cut -d':' -f2)
SRV_LOC=$(echo "$RESULT" | grep -o '"location":"[^"]*"' | head -1 | cut -d'"' -f4)
SRV_CC=$(echo "$RESULT" | grep -o '"country":"[^"]*"' | head -1 | cut -d'"' -f4)
RESULT_URL=$(echo "$RESULT" | grep -o '"url":"[^"]*"' | head -1 | cut -d'"' -f4)
ISP_OOKLA=$(echo "$RESULT" | grep -o '"isp":"[^"]*"' | head -1 | cut -d'"' -f4)

[ -z "$PING" ] && PING=0
[ -z "$PING_JITTER" ] && PING_JITTER=0
[ -z "$DL_BW" ] && DL_BW=0
[ -z "$UL_BW" ] && UL_BW=0
[ -z "$ISP_OOKLA" ] && ISP_OOKLA="Unknown"

DL=$(awk "BEGIN { printf \"%.1f\", $DL_BW * 8 / 1000000 }")
UL=$(awk "BEGIN { printf \"%.1f\", $UL_BW * 8 / 1000000 }")
PING=$(awk "BEGIN { printf \"%.0f\", $PING }")
PING_JITTER=$(awk "BEGIN { printf \"%.1f\", $PING_JITTER }")

printf "  ${GR}✓${R} IP Anda    : ${B}${WH}${IP_ADDR}${R}\n"
printf "  ${GR}✓${R} Lokasi     : ${B}${WH}${SRV_LOC}, ${SRV_CC}${R}\n"
printf "  ${GR}✓${R} ISP        : ${B}${WH}${ISP_OOKLA}${R}\n"
printf "  ${GR}✓${R} Ping       : ${B}${YL}${PING} ms${R} ${D}(jitter: ${PING_JITTER} ms)${R}\n"
printf "  ${GR}✓${R} Download   : ${B}${CY}${DL} Mbps${R}\n"
printf "  ${GR}✓${R} Upload     : ${B}${GR}${UL} Mbps${R}\n"
printf "  ${GR}✓${R} Netflix    : ${B}${MG}${NF_NAME} (${NF_LOC})${R}\n"

printf "\n  ${CY}══════════════════════════════════════════${R}\n"
printf "  ${B}${WH}   HASIL AKHIR${R}\n"
printf "  ${CY}══════════════════════════════════════════${R}\n"
printf "     ${WH}Ping       ${R}  ${B}${YL}%s ms${R}\n" "$PING"
printf "     ${WH}Download   ${R}  ${B}${CY}%s Mbps${R}\n" "$DL"
printf "     ${WH}Upload     ${R}  ${B}${GR}%s Mbps${R}\n" "$UL"
printf "  ${CY}══════════════════════════════════════════${R}\n"

printf "\n  ${B}${RD}▶ YOUTUBE QUALITY${R}\n"
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

BEST="Tidak cukup"
awk "BEGIN { exit !($DL >= 35) }" && BEST="4K (2160p)"
awk "BEGIN { exit !($DL >= 16 && $DL < 35) }" && BEST="2K (1440p)"
awk "BEGIN { exit !($DL >= 8 && $DL < 16) }" && BEST="1080p (FHD)"
awk "BEGIN { exit !($DL >= 5 && $DL < 8) }" && BEST="720p (HD)"
awk "BEGIN { exit !($DL >= 2.5 && $DL < 5) }" && BEST="480p"
awk "BEGIN { exit !($DL >= 1 && $DL < 2.5) }" && BEST="360p"
awk "BEGIN { exit !($DL >= 0.3 && $DL < 1) }" && BEST="240p"
awk "BEGIN { exit !($DL >= 0.1 && $DL < 0.3) }" && BEST="144p"

printf "  ${B}${WH}Kualiti tertinggi :${R}  ${B}${RD}▶ ${BEST}${R}\n"

if [ -n "$RESULT_URL" ] && [ "$RESULT_URL" != "null" ]; then
  printf "\n  ${WH}Result URL:${R}\n  ${CY}${RESULT_URL}${R}\n"
fi

LOG="${TMP_BASE}/speedtest.log"
{
  echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="
  echo "Engine    : Speedtest.net (Ookla)"
  echo "IP        : $IP_ADDR"
  echo "Netflix   : $NF_NAME ($NF_LOC)"
  echo "Lokasi    : $SRV_LOC, $SRV_CC"
  echo "ISP       : $ISP_OOKLA"
  echo "Ping      : $PING ms (jitter: $PING_JITTER ms)"
  echo "Download  : $DL Mbps"
  echo "Upload    : $UL Mbps"
  echo "YouTube   : $BEST"
  [ -n "$RESULT_URL" ] && echo "URL       : $RESULT_URL"
  echo ""
} >> "$LOG" 2>/dev/null

printf "\n  ${D}${GY}Log: ${LOG}${R}\n\n"
ENDOFSCRIPT
chmod +x /usr/bin/Speedtest
echo ""
echo "✓ Setup selesai! Jalankan: Speedtest"
echo ""