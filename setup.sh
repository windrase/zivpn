#!/bin/bash
# WINTUNELING VPN - PROFESSIONAL EDITION
# Features: Telegram Notif, Landing Page, Table View for Delete/Renew

# ==========================================
# CONFIGURATION
# ==========================================
LICENSE_URL="http://129.226.206.227:3000/whitelist"
DIR="/etc/zivpn"
DIR_API="$DIR/api"
DB="$DIR/user.db"
CONFIG="$DIR/config.json"
API_KEY_FILE="$DIR/apikey"
TG_CONFIG="$DIR/tg_backup.conf"
SERVICE_VPN="zivpn.service"
SERVICE_API="zivpn-api.service"
BIN="/usr/local/bin/zivpn"
MENU_BIN="/usr/local/bin/menu"
BACKUP_BIN="/usr/local/bin/backup-tg"
LANDING_BIN="/usr/bin/landing-page"

# Colors
CYAN='\033[0;36m'
WHITE='\033[0;37m'
GRAY='\033[0;90m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

# ==========================================
# 1. SYSTEM PREPARATION
# ==========================================
clear
echo -e "${CYAN}[1/7] Preparing System...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y >/dev/null 2>&1
apt-get install -y curl wget jq openssl zip unzip cron net-tools lsb-release gnupg vnstat bc neofetch >/dev/null 2>&1

# Vnstat Setup
systemctl enable vnstat
systemctl start vnstat
INTF=$(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1)
sed -i "s/Interface \".*\"/Interface \"$INTF\"/g" /etc/vnstat.conf
systemctl restart vnstat

# Node.js for API
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash - >/dev/null 2>&1
    apt-get install -y nodejs >/dev/null 2>&1
fi

# ==========================================
# 2. INSTALL CORE & API
# ==========================================
echo -e "${CYAN}[2/7] Installing Core...${NC}"
systemctl stop $SERVICE_VPN >/dev/null 2>&1
mkdir -p $DIR $DIR_API

# Domain Logic
if [ -f /etc/xray/domain ]; then
    DOMAIN_INPUT=$(cat /etc/xray/domain)
else
    if [ -f "$DIR/zivpn.crt" ]; then
        DOMAIN_INPUT=$(openssl x509 -noout -subject -in $DIR/zivpn.crt | sed -n 's/^.*CN = //p')
    else
        DOMAIN_INPUT=$(curl -s ipv4.icanhazip.com)
    fi
fi

# Download Binary
ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
    wget -q https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64 -O $BIN
else
    wget -q https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-arm64 -O $BIN
fi
chmod +x $BIN

# Certificate
if [ ! -f "$DIR/zivpn.crt" ]; then
    openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
        -subj "/C=ID/ST=VPN/L=VPN/O=WINTUNNELING/CN=$DOMAIN_INPUT" \
        -keyout "$DIR/zivpn.key" -out "$DIR/zivpn.crt" >/dev/null 2>&1
fi

# Config JSON
if [ ! -f "$CONFIG" ]; then
    echo '{"listen": ":5667", "cert": "'$DIR'/zivpn.crt", "key": "'$DIR'/zivpn.key", "obfs": "zivpn", "auth": {"mode": "passwords", "config": ["default"]}}' > $CONFIG
fi
touch $DB

# Service VPN
cat <<EOF > /etc/systemd/system/$SERVICE_VPN
[Unit]
Description=ZIVPN Core
After=network.target
[Service]
Type=simple
User=root
WorkingDirectory=$DIR
ExecStart=$BIN server -c $CONFIG
Restart=always
RestartSec=3
Environment=ZIVPN_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true
[Install]
WantedBy=multi-user.target
EOF

# API Server
if [ ! -f "$API_KEY_FILE" ]; then openssl rand -hex 3 > $API_KEY_FILE; fi
cd $DIR_API
if [ ! -f "package.json" ]; then npm init -y >/dev/null 2>&1; npm install express shelljs body-parser >/dev/null 2>&1; fi

cat << 'EOF' > server.js
const express = require('express');
const shell = require('shelljs');
const fs = require('fs');
const app = express();
const port = 5888;
const DB_FILE = '/etc/zivpn/user.db';
const API_KEY_FILE = '/etc/zivpn/apikey';
app.use(express.urlencoded({ extended: true }));
app.use(express.json());
const checkAuth = (req, res, next) => {
    const auth = req.query.auth || req.body.auth;
    let validKey = '';
    try { validKey = fs.readFileSync(API_KEY_FILE, 'utf8').trim(); } catch (e) {}
    if (auth === validKey && validKey !== '') next(); else res.json({ status: 'error', message: 'API Key Invalid' });
};
function sync() { shell.exec('systemctl restart zivpn'); }
app.listen(port, () => console.log(`API running on ${port}`));
EOF

cat <<EOF > /etc/systemd/system/$SERVICE_API
[Unit]
Description=ZIVPN API
After=network.target
[Service]
Type=simple
User=root
WorkingDirectory=$DIR_API
ExecStart=/usr/bin/node server.js
Restart=always
[Install]
WantedBy=multi-user.target
EOF

# Firewall
iptables -t nat -A PREROUTING -i $INTF -p udp --dport 6000:19999 -j DNAT --to-destination :5667

# ==========================================
# 3. NOTIFICATION SYSTEM
# ==========================================
echo -e "${CYAN}[3/7] Installing Notification System...${NC}"

cat << 'EOF' > $BACKUP_BIN
#!/bin/bash
TG_CONFIG="/etc/zivpn/tg_backup.conf"
if [ ! -f "$TG_CONFIG" ]; then echo "Telegram not configured"; exit 0; fi
source $TG_CONFIG

DATE=$(date +%Y-%m-%d)
TIME=$(date +%H:%M:%S)
IP=$(curl -s ipv4.icanhazip.com)
FILENAME="backup-$IP-$DATE.zip"

cd /root
zip -r $FILENAME /etc/zivpn/user.db /etc/zivpn/config.json /etc/zivpn/apikey /etc/zivpn/zivpn.crt /etc/zivpn/zivpn.key > /dev/null 2>&1

CAPTION="🤖 *WINTUNELING AUTO BACKUP*
━━━━━━━━━━━━━━━━━━━━
📅 Date  : \`$DATE\`
⏰ Time  : \`$TIME\`
🌐 IP    : \`$IP\`
━━━━━━━━━━━━━━━━━━━━"

curl -F chat_id="$TG_ID" -F document=@"$FILENAME" -F caption="$CAPTION" -F parse_mode="Markdown" "https://api.telegram.org/bot$TG_TOKEN/sendDocument" > /dev/null 2>&1
rm $FILENAME
EOF
chmod +x $BACKUP_BIN

# ==========================================
# 4. MENU SCRIPT (WINTUNELING EDITION)
# ==========================================
echo -e "${CYAN}[4/7] Installing Menu...${NC}"

cat << 'END_OF_MENU' > $MENU_BIN
#!/bin/bash
# ZIVPN MENU - WINTUNELING EDITION

DIR="/etc/zivpn"
DB="$DIR/user.db"
CONFIG="$DIR/config.json"
API_KEY_FILE="$DIR/apikey"
TG_CONFIG="$DIR/tg_backup.conf"
SERVICE="zivpn"
SERVICE_API="zivpn-api"

# Colors
CYAN='\033[0;36m'
WHITE='\033[0;37m'
GRAY='\033[0;90m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'
YELLOW='\033[0;33m'

function send_log() {
    if [ ! -f "$TG_CONFIG" ]; then return; fi
    source "$TG_CONFIG"
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
        -d chat_id="${TG_ID}" \
        -d parse_mode="html" \
        --data-urlencode text="${message}" > /dev/null 2>&1
}

function get_info() {
    OS=$(lsb_release -d | cut -f2 | tr -d '"' | sed 's/Ubuntu //')
    ISP=$(curl -s ip-api.com/json | jq -r .isp)
    IP=$(curl -s ipv4.icanhazip.com)
    HOST=$(hostname)
    [ -z "$HOST" ] && HOST="$IP"
    DOMAIN=$(openssl x509 -noout -subject -in $DIR/zivpn.crt | sed -n 's/^.*CN = //p')
    
    CLIENT=$(cat /etc/wintunnel/client 2>/dev/null || echo "ZIVPN-User")
    EXP_DATE=$(cat /etc/wintunnel/exp 2>/dev/null || echo "Lifetime")
    d1=$(date -d "$EXP_DATE" +%s 2>/dev/null)
    d2=$(date -d "$(date +%Y-%m-%d)" +%s)
    if [[ ! -z "$d1" ]]; then
        diff=$(( ($d1 - $d2) / 86400 ))
        [ $diff -lt 0 ] && DAYS_LEFT="Expired" || DAYS_LEFT="$diff days"
    else
        DAYS_LEFT="-"
    fi

    RAM_USED=$(free -m | awk 'NR==2{print $3}')
    RAM_TOTAL=$(free -m | awk 'NR==2{print $2}')
    RAM_PERC=$(awk "BEGIN {printf \"%.0f\", $RAM_USED/$RAM_TOTAL*100}")
    DISK_USED=$(df -h / | awk 'NR==2{print $3}')
    DISK_TOTAL=$(df -h / | awk 'NR==2{print $2}')
    DISK_PERC=$(df -h / | awk 'NR==2{print $5}')
    CPU_MODEL=$(lscpu | grep "Model name" | cut -d: -f2 | sed 's/^ //;s/  */ /g' | cut -c1-25)
    CPU_CORES=$(nproc)
    UPTIME=$(uptime -p | sed 's/up //')
    
    INTF=$(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1)
    VN_TODAY=$(vnstat -i $INTF --oneline | awk -F';' '{print $6}')
    VN_MONTH=$(vnstat -i $INTF --oneline | awk -F';' '{print $11}')
    [ -z "$VN_TODAY" ] && VN_TODAY="0 B"
    [ -z "$VN_MONTH" ] && VN_MONTH="0 B"
    
    USERS=$(wc -l < $DB 2>/dev/null || echo "0")
    API_KEY=$(cat $API_KEY_FILE 2>/dev/null)

    if systemctl is-active --quiet $SERVICE; then STAT_VPN="${GREEN}Running${NC}"; else STAT_VPN="${RED}Stopped${NC}"; fi
    if systemctl is-active --quiet $SERVICE_API; then STAT_API="${GREEN}Running${NC}"; else STAT_API="${RED}Stopped${NC}"; fi
}

function show_menu() {
    clear
    get_info
    echo -e "${CYAN} _   _ ____  ____    __________     ______  _   _ ${NC}"
    echo -e "${CYAN}| | | |  _ \|  _ \  |__  /_ _\ \   / /  _ \| \ | |${NC}"
    echo -e "${CYAN}| | | | | | | |_) |   / / | | \ \ / /| |_) |  \| |${NC}"
    echo -e "${CYAN}| |_| | |_| |  __/   / /_ | |  \ V / |  __/| |\  |${NC}"
    echo -e "${CYAN} \___/|____/|_|     /____|___|  \_/  |_|   |_| \_|${NC}"
    echo -e "${CYAN}┌──────────────// WINTUNELING VPN //─────────────────┐${NC}"
    printf "  %-7s %-20s %-6s %-20s\n" "OS:" "${OS:0:20}" "ISP:" "${ISP:0:23}"
    printf "  %-7s %-20s %-6s %-20s\n" "IP:" "$IP" "Host:" "${DOMAIN:0:23}"
    printf "  %-7s %-20s %-6s %-20s\n" "Client:" "${CLIENT:0:15}" "EXP:" "$DAYS_LEFT"
    printf "  %-7s %-20s %-6s %-20s\n" "Today:" "$VN_TODAY" "Month:" "$VN_MONTH"
    printf "  %-7s %-19s %-6s %-20s\n" "RAM:" "${RAM_USED}Mi/${RAM_TOTAL}Mi ($RAM_PERC%)" "Disk:" "${DISK_USED}/${DISK_TOTAL} ($DISK_PERC)"
    printf "  %-7s %-40s\n" "CPU:" "$CPU_MODEL ($CPU_CORES cores)"
    printf "  %-7s %-40s\n" "Uptime:" "$UPTIME"
    printf "  %-7s %-20s\n" "Users:" "$USERS"
    printf "  %-7s %-20s\n" "API Key:" "$API_KEY"
    echo -e "${CYAN}├────────────────────────────────────────────────────┤${NC}"
    echo -e "                    ZiVPN: $STAT_VPN"
    echo -e "                  ZiVPN API: $STAT_API"
    echo -e "${CYAN}├────────────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│                                                    │${NC}"
    echo -e "${CYAN}│${NC}   1) Create Account                                ${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}   2) Create Trial Account                          ${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}   3) Renew Account                                 ${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}   4) Delete Account                                ${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}   5) List Accounts                                 ${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}   6) Change Domain                                 ${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}   7) Backup/Restore                                ${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}   8) Setup Telegram Notif                          ${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}   9) Restart Service                               ${CYAN}│${NC}"
    echo -e "${CYAN}│${NC}   0) Exit                                          ${CYAN}│${NC}"
    echo -e "${CYAN}│                                                    │${NC}"
    echo -e "${CYAN}└────────────────────────────────────────────────────┘${NC}"
    echo -ne "Enter your choice [0-9]: "
    read opt
    case $opt in
        1) create_user ;;
        2) trial_user ;;
        3) renew_user ;;
        4) delete_user ;;
        5) list_user ;;
        6) change_domain ;;
        7) backup_menu ;;
        8) setup_telegram ;;
        9) systemctl restart $SERVICE; echo "Service Restarted"; sleep 1 ;;
        0) exit 0 ;;
        *) echo "Invalid Option"; sleep 1 ;;
    esac
}

function sync_config() {
    PASS_LIST=$(awk -F: '{printf "\"%s\",", $2}' $DB | sed 's/,$//')
    [ -z "$PASS_LIST" ] && PASS_LIST="\"default\""
    jq ".auth.config = [$PASS_LIST]" $CONFIG > $CONFIG.tmp && mv $CONFIG.tmp $CONFIG
    systemctl restart $SERVICE
}

function create_user() {
    echo -e "\n${CYAN}[ CREATE ACCOUNT ]${NC}"
    read -p "Password : " pass
    user="$pass"
    if grep -q "^$user:" $DB; then echo -e "${RED}User/Pass exists!${NC}"; sleep 1; return; fi
    read -p "Exp Days : " days
    exp=$(($(date +%s) + days * 86400))
    echo "$user:$pass:$exp" >> $DB
    sync_config
    
    exp_date=$(date -d @$exp "+%d %b %Y")
    echo -e "${GREEN}Account Created!${NC}"
    
    get_info
    TEXT="<code><b>✅ NEW ACCOUNT CREATED</b>
━━━━━━━━━━━━━━━━━━━━
<b>Domain :</b> <code>${DOMAIN}</code>
<b>Pass   :</b> <code>${pass}</code>
<b>Exp    :</b> <code>${exp_date}</code>
━━━━━━━━━━━━━━━━━━━━
<i>By WINTUNELING VPN</i></code>"
    send_log "$TEXT"
    
    echo -e "Check Telegram for details."
    read -p "Press Enter..."
}

function trial_user() {
    echo -e "\n${CYAN}[ TRIAL ACCOUNT ]${NC}"
    read -p "Duration (Min): " mins
    user="trial$(date +%s | tail -c 4)"
    pass=$user
    exp=$(($(date +%s) + mins * 60))
    echo "$user:$pass:$exp" >> $DB
    sync_config
    
    echo -e "${GREEN}Trial Created!${NC}"
    get_info
    TEXT="<code><b>⏳ TRIAL ACCOUNT CREATED</b>
━━━━━━━━━━━━━━━━━━━━
<b>Domain :</b> <code>${DOMAIN}</code>
<b>Pass   :</b> <code>${pass}</code>
<b>Exp    :</b> <code>${mins} Minutes</code>
━━━━━━━━━━━━━━━━━━━━
<i>By WINTUNELING VPN</i></code>"
    send_log "$TEXT"
    
    read -p "Press Enter..."
}

function delete_user() {
    clear
    echo -e "${CYAN}┌─────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│                  DELETE ACCOUNT                         │${NC}"
    echo -e "${CYAN}├────┬──────────────────┬──────────────────┬──────────────┤${NC}"
    echo -e "${CYAN}│ NO │       USER       │     PASSWORD     │   EXPIRED    │${NC}"
    echo -e "${CYAN}├────┼──────────────────┼──────────────────┼──────────────┤${NC}"
    i=1
    while IFS=: read -r u p e; do
        exp_date=$(date -d @$e +%F)
        printf "${CYAN}│ %-2s │ %-16s │ %-16s │ %-12s │${NC}\n" "$i" "$u" "$p" "$exp_date"
        users[$i]=$u
        ((i++))
    done < $DB
    echo -e "${CYAN}└────┴──────────────────┴──────────────────┴──────────────┘${NC}"
    echo -ne "Select number to delete (0 to cancel): "
    read num
    if [[ "$num" == "0" ]]; then return; fi
    target=${users[$num]}
    if [ -n "$target" ]; then
        grep -v "^$target:" $DB > $DB.tmp && mv $DB.tmp $DB
        sync_config
        echo -e "${GREEN}Deleted $target${NC}"
    else
        echo -e "${RED}Invalid Number${NC}"
    fi
    read -p "Press Enter..."
}

function renew_user() {
    clear
    echo -e "${CYAN}┌─────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│                   RENEW ACCOUNT                         │${NC}"
    echo -e "${CYAN}├────┬──────────────────┬──────────────────┬──────────────┤${NC}"
    echo -e "${CYAN}│ NO │       USER       │     PASSWORD     │   EXPIRED    │${NC}"
    echo -e "${CYAN}├────┼──────────────────┼──────────────────┼──────────────┤${NC}"
    i=1
    while IFS=: read -r u p e; do
        exp_date=$(date -d @$e +%F)
        printf "${CYAN}│ %-2s │ %-16s │ %-16s │ %-12s │${NC}\n" "$i" "$u" "$p" "$exp_date"
        users[$i]=$u
        ((i++))
    done < $DB
    echo -e "${CYAN}└────┴──────────────────┴──────────────────┴──────────────┘${NC}"
    echo -ne "Select number to renew (0 to cancel): "
    read num
    if [[ "$num" == "0" ]]; then return; fi
    target=${users[$num]}
    if [ -n "$target" ]; then
        read -p "Add Days: " d
        grep -v "^$target:" $DB > $DB.tmp
        # Asumsi user=pass. Jika mau mempertahankan pass lama, kita harus baca dulu
        # Tapi karena format db hanya u:p:e dan kita replace, kita ambil dari var memory
        # Namun di loop tadi $p tidak disimpan ke array. Kita baca ulang saja biar aman:
        line=$(grep "^$target:" $DB)
        old_pass=$(echo $line | cut -d: -f2)
        echo "$target:$old_pass:$(($(date +%s) + d * 86400))" >> $DB.tmp
        mv $DB.tmp $DB
        sync_config
        echo -e "${GREEN}Renewed $target for $d days.${NC}"
    else
        echo -e "${RED}Invalid Number${NC}"
    fi
    read -p "Press Enter..."
}

function list_user() {
    clear
    echo -e "${CYAN}List Accounts:${NC}"
    echo "---------------------------------------------------------"
    printf "%-20s %-20s %-15s\n" "User" "Password" "Expired"
    echo "---------------------------------------------------------"
    while IFS=: read -r u p e; do
        printf "%-20s %-20s %-15s\n" "$u" "$p" "$(date -d @$e +%F)"
    done < $DB
    echo "---------------------------------------------------------"
    read -p "Press Enter..."
}

function change_domain() {
    read -p "New Domain: " d
    openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 -subj "/C=ID/CN=$d" -keyout $DIR/zivpn.key -out $DIR/zivpn.crt >/dev/null 2>&1
    systemctl restart $SERVICE
    echo "Domain changed to $d"
    read -p "Press Enter..."
}

function backup_menu() {
    echo -e "1) Backup Now to Telegram"
    echo -e "2) Restore from URL"
    read -p "Choice: " c
    if [ "$c" == "1" ]; then
        /usr/local/bin/backup-tg
        echo "Backup sent!"
    elif [ "$c" == "2" ]; then
        read -p "URL: " u
        wget -O backup.zip "$u" && unzip -o backup.zip -d / && systemctl restart $SERVICE
        echo "Restored."
    fi
    read -p "Press Enter..."
}

function setup_telegram() {
    read -p "Bot Token: " t
    read -p "Chat ID: " c
    echo "TG_TOKEN='$t'" > $TG_CONFIG
    echo "TG_ID='$c'" >> $TG_CONFIG
    echo "Saved."
    send_log "✅ Telegram Connected!"
    read -p "Press Enter..."
}

while true; do show_menu; done
END_OF_MENU

chmod +x $MENU_BIN

# ==========================================
# 5. LANDING PAGE (PREVIEW)
# ==========================================
echo -e "${CYAN}[5/7] Installing Landing Page...${NC}"

cat > $LANDING_BIN << 'EOF'
#!/bin/bash
# Landing Page Preview

# Colors
CYAN='\033[0;36m'
WHITE='\033[0;37m'
GRAY='\033[0;90m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

DIR="/etc/zivpn"
DB="$DIR/user.db"
API_KEY_FILE="$DIR/apikey"

# System Info
OS=$(lsb_release -d | cut -f2 | tr -d '"' | sed 's/Ubuntu //')
ISP=$(curl -s ip-api.com/json | jq -r .isp)
IP=$(curl -s ipv4.icanhazip.com)
DOMAIN=$(cat /etc/xray/domain 2>/dev/null || openssl x509 -noout -subject -in $DIR/zivpn.crt 2>/dev/null | sed -n 's/^.*CN = //p')
[ -z "$DOMAIN" ] && DOMAIN="$IP"

CLIENT=$(cat /etc/wintunnel/client 2>/dev/null || echo "ZIVPN-User")
EXP_DATE=$(cat /etc/wintunnel/exp 2>/dev/null || echo "Lifetime")
d1=$(date -d "$EXP_DATE" +%s 2>/dev/null)
d2=$(date -d "$(date +%Y-%m-%d)" +%s)
if [[ ! -z "$d1" ]]; then
    diff=$(( ($d1 - $d2) / 86400 ))
    [ $diff -lt 0 ] && DAYS_LEFT="Expired" || DAYS_LEFT="$diff days"
else
    DAYS_LEFT="-"
fi

RAM_USED=$(free -m | awk 'NR==2{print $3}')
RAM_TOTAL=$(free -m | awk 'NR==2{print $2}')
RAM_PERC=$(awk "BEGIN {printf \"%.0f\", $RAM_USED/$RAM_TOTAL*100}")
DISK_USED=$(df -h / | awk 'NR==2{print $3}')
DISK_TOTAL=$(df -h / | awk 'NR==2{print $2}')
DISK_PERC=$(df -h / | awk 'NR==2{print $5}')
CPU_MODEL=$(lscpu | grep "Model name" | cut -d: -f2 | sed 's/^ //;s/  */ /g' | cut -c1-25)
CPU_CORES=$(nproc)
UPTIME=$(uptime -p | sed 's/up //')
USERS=$(wc -l < $DB 2>/dev/null || echo "0")
API_KEY=$(cat $API_KEY_FILE 2>/dev/null)

INTF=$(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1)
VN_TODAY=$(vnstat -i $INTF --oneline | awk -F';' '{print $6}')
VN_MONTH=$(vnstat -i $INTF --oneline | awk -F';' '{print $11}')
[ -z "$VN_TODAY" ] && VN_TODAY="0 B"
[ -z "$VN_MONTH" ] && VN_MONTH="0 B"

if systemctl is-active --quiet zivpn; then STAT_VPN="${GREEN}Running${NC}"; else STAT_VPN="${RED}Stopped${NC}"; fi
if systemctl is-active --quiet zivpn-api; then STAT_API="${GREEN}Running${NC}"; else STAT_API="${RED}Stopped${NC}"; fi

clear
echo -e "${CYAN} _   _ ____  ____    __________     ______  _   _ ${NC}"
echo -e "${CYAN}| | | |  _ \|  _ \  |__  /_ _\ \   / /  _ \| \ | |${NC}"
echo -e "${CYAN}| | | | | | | |_) |   / / | | \ \ / /| |_) |  \| |${NC}"
echo -e "${CYAN}| |_| | |_| |  __/   / /_ | |  \ V / |  __/| |\  |${NC}"
echo -e "${CYAN} \___/|____/|_|     /____|___|  \_/  |_|   |_| \_|${NC}"
echo -e "${CYAN}┌──────────────// WINTUNELING VPN //─────────────────┐${NC}"
printf "  %-7s %-20s %-6s %-20s\n" "OS:" "${OS:0:20}" "ISP:" "${ISP:0:23}"
printf "  %-7s %-20s %-6s %-20s\n" "IP:" "$IP" "Host:" "${DOMAIN:0:23}"
printf "  %-7s %-20s %-6s %-20s\n" "Client:" "${CLIENT:0:15}" "EXP:" "$DAYS_LEFT"
printf "  %-7s %-20s %-6s %-20s\n" "Today:" "$VN_TODAY" "Month:" "$VN_MONTH"
printf "  %-7s %-19s %-6s %-20s\n" "RAM:" "${RAM_USED}Mi/${RAM_TOTAL}Mi ($RAM_PERC%)" "Disk:" "${DISK_USED}/${DISK_TOTAL} ($DISK_PERC)"
printf "  %-7s %-40s\n" "CPU:" "$CPU_MODEL ($CPU_CORES cores)"
printf "  %-7s %-40s\n" "Uptime:" "$UPTIME"
printf "  %-7s %-20s\n" "Users:" "$USERS"
printf "  %-7s %-20s\n" "API Key:" "$API_KEY"
echo -e "${CYAN}├────────────────────────────────────────────────────┤${NC}"
echo -e "                    ZiVPN: $STAT_VPN"
echo -e "                  ZiVPN API: $STAT_API"
echo -e "${CYAN}├────────────────────────────────────────────────────┤${NC}"
echo -e "${CYAN}│                                                    │${NC}"
echo -e "${CYAN}│${WHITE}           TEKAN [ ENTER ] UNTUK MEMBUKA MENU       ${CYAN}│${NC}"
echo -e "${CYAN}│                                                    │${NC}"
echo -e "${CYAN}└────────────────────────────────────────────────────┘${NC}"
read -n 1 -s -r -p ""
menu
EOF

chmod +x $LANDING_BIN

# ==========================================
# 6. FINISHING
# ==========================================
# Force landing page on login
sed -i '/landing-page/d' ~/.profile
cat >> ~/.profile << 'EOF'
if [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ]; then
    /usr/bin/landing-page
fi
EOF

systemctl daemon-reload
systemctl enable $SERVICE_VPN $SERVICE_API
systemctl start $SERVICE_VPN $SERVICE_API

clear
echo -e "${GREEN}=========================================${NC}"
echo -e "${YELLOW}       INSTALLATION SUCCESSFUL!          ${NC}"
echo -e "${GREEN}=========================================${NC}"
echo -e " Ketik 'menu' untuk akses."
echo -e " Rebooting 5s..."
sleep 5
reboot
