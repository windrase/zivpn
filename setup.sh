#!/bin/bash

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

# IP REGISTER & EXPIRED CHECK
clear
echo -e "${YELLOW}[INFO] Checking License Registration...${NC}"
MYIP=$(curl -s ipv4.icanhazip.com)
LICENSE_DATA=$(curl -s --connect-timeout 5 "$LICENSE_URL")

if echo "$LICENSE_DATA" | grep -q "$MYIP"; then
    DATA_CLIENT=$(echo "$LICENSE_DATA" | grep "$MYIP")
    CLIENT_NAME=$(echo "$DATA_CLIENT" | cut -d: -f2)
    EXP_DATE=$(echo "$DATA_CLIENT" | cut -d: -f3)
    TODAY=$(date +%Y-%m-%d)

    if [[ "$TODAY" > "$EXP_DATE" ]]; then
        echo -e "${RED}⛔ LICENSE EXPIRED!${NC}"
        echo -e "${RED}Your license expired on: $EXP_DATE${NC}"
         echo -e "${RED}Contact t.me/WINTUNELINGVPNN For LICENSE SCRIPT: $EXP_DATE${NC}"
        exit 1
    else
        echo -e "${GREEN}✅ LICENSE ACTIVE!${NC}"
        echo -e "Client : $CLIENT_NAME"
        echo -e "Expired: $EXP_DATE"
        
        mkdir -p /etc/wintunnel
        echo "$CLIENT_NAME" > /etc/wintunnel/client
        echo "$EXP_DATE" > /etc/wintunnel/exp
        sleep 2
    fi
else
    echo -e "${RED}⛔ ACCESS DENIED!${NC}"
    echo -e "${RED}Your IP ($MYIP) is not registered.${NC}"
    exit 1
fi

# SYSTEM PREPARATION
echo -e "${CYAN}[1/7] Preparing System...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y >/dev/null 2>&1
apt-get install -y curl wget jq openssl zip unzip cron net-tools lsb-release gnupg vnstat bc neofetch >/dev/null 2>&1

systemctl enable vnstat
systemctl start vnstat
INTF=$(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1)
sed -i "s/Interface \".*\"/Interface \"$INTF\"/g" /etc/vnstat.conf
systemctl restart vnstat

if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash - >/dev/null 2>&1
    apt-get install -y nodejs >/dev/null 2>&1
fi

# INSTALL CORE & API
echo -e "${CYAN}[2/7] Installing Core...${NC}"
systemctl stop $SERVICE_VPN >/dev/null 2>&1
mkdir -p $DIR $DIR_API

if [ -f /etc/xray/domain ]; then
    DOMAIN_INPUT=$(cat /etc/xray/domain)
else
    if [ -f "$DIR/zivpn.crt" ]; then
        DOMAIN_INPUT=$(openssl x509 -noout -subject -in $DIR/zivpn.crt | sed -n 's/^.*CN = //p')
    else
        DOMAIN_INPUT=$(curl -s ipv4.icanhazip.com)
    fi
fi

ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
    wget -q https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64 -O $BIN
else
    wget -q https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-arm64 -O $BIN
fi
chmod +x $BIN

if [ ! -f "$DIR/zivpn.crt" ]; then
    openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
        -subj "/C=ID/ST=VPN/L=VPN/O=WINTUNNELING/CN=$DOMAIN_INPUT" \
        -keyout "$DIR/zivpn.key" -out "$DIR/zivpn.crt" >/dev/null 2>&1
fi

if [ ! -f "$CONFIG" ]; then
    echo '{"listen": ":5667", "cert": "'$DIR'/zivpn.crt", "key": "'$DIR'/zivpn.key", "obfs": "zivpn", "auth": {"mode": "passwords", "config": ["default"]}}' > $CONFIG
fi
touch $DB

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

iptables -t nat -A PREROUTING -i $INTF -p udp --dport 6000:19999 -j DNAT --to-destination :5667


#  NOTIFICATION & AUTO BACKUP SYSTEM
echo -e "${CYAN}[3/7] Installing Auto Backup System (00:00)...${NC}"

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

CAPTION="✅ *AUTO BACKUP SUCCESFULLY*
━━━━━━━━━━━━━━━━━━━━
📅 Date  : \`$DATE\`
⏰ Time  : \`$TIME\`
🌐 IP    : \`$IP\`
━━━━━━━━━━━━━━━━━━━━"

curl -F chat_id="$TG_ID" -F document=@"$FILENAME" -F caption="$CAPTION" -F parse_mode="Markdown" "https://api.telegram.org/bot$TG_TOKEN/sendDocument" > /dev/null 2>&1
rm $FILENAME
EOF
chmod +x $BACKUP_BIN

# --- SETUP CRONJOB (00:00) ---
crontab -l | grep -v "backup-tg" | crontab -
(crontab -l 2>/dev/null; echo "0 0 * * * /usr/local/bin/backup-tg") | crontab -
service cron restart
echo -e "${GREEN}✅ Auto Backup scheduled at 00:00${NC}"

# ==========================================
# 5. MENU SCRIPT (CLEAN WIDGET)
# ==========================================
echo -e "${CYAN}[4/7] Installing Menu...${NC}"

cat << 'END_OF_MENU' > /usr/local/bin/menu
#!/bin/bash
DIR="/etc/zivpn"
DB="$DIR/user.db"
CONFIG="$DIR/config.json"
API_KEY_FILE="$DIR/apikey"
TG_CONFIG="$DIR/tg_backup.conf"
SERVICE="zivpn"
SERVICE_API="zivpn-api"

CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

function get_info() {
    OS=$(lsb_release -d | cut -f2 | tr -d '"' | sed 's/Ubuntu //')
    IP=$(curl -s ipv4.icanhazip.com)
    DOMAIN=$(openssl x509 -noout -subject -in $DIR/zivpn.crt 2>/dev/null | sed -n 's/^.*CN = //p')
    [ -z "$DOMAIN" ] && DOMAIN="No Domain"
    ISP=$(curl -s ip-api.com/json | jq -r .isp)
    CLIENT=$(cat /etc/wintunnel/client 2>/dev/null || echo "User")
    EXP_DATE=$(cat /etc/wintunnel/exp 2>/dev/null || echo "Lifetime")
    RAM_USED=$(free -m | awk 'NR==2{print $3}')
    RAM_TOTAL=$(free -m | awk 'NR==2{print $2}')
    RAM_PERC=$(awk "BEGIN {printf \"%.0f\", $RAM_USED/$RAM_TOTAL*100}")
    CPU_MODEL=$(lscpu | grep "Model name" | cut -d: -f2 | sed 's/^ //;s/  */ /g' | cut -c1-20)
    UPTIME=$(uptime -p | sed 's/up //')
    USERS=$(wc -l < $DB 2>/dev/null || echo "0")
}

function show_menu() {
    clear
    get_info
    echo -e "${CYAN}┌──────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${NC}              WINTUNELING VPN PANEL               ${CYAN}│${NC}"
    echo -e "${CYAN}├──────────────────────────────────────────────────┤${NC}"
    printf "${CYAN}│${NC} %-8s: %-19s│ %-5s: %-11s${CYAN}│${NC}\n" "OS" "${OS:0:19}" "IP" "$IP"
    printf "${CYAN}│${NC} %-8s: %-19s│ %-5s: %-11s${CYAN}│${NC}\n" "Domain" "${DOMAIN:0:19}" "ISP" "${ISP:0:11}"
    echo -e "${CYAN}├──────────────────────────────────────────────────┤${NC}"
    printf "${CYAN}│${NC} %-8s: %-19s│ %-5s: %-11s${CYAN}│${NC}\n" "Client" "${CLIENT:0:15}" "EXP" "$EXP_DATE"
    echo -e "${CYAN}├──────────────────────────────────────────────────┤${NC}"
    printf "${CYAN}│${NC} %-8s: %-37s${CYAN}│${NC}\n" "RAM" "$RAM_USED/$RAM_TOTAL MB ($RAM_PERC%)"
    printf "${CYAN}│${NC} %-8s: %-37s${CYAN}│${NC}\n" "CPU" "$CPU_MODEL"
    printf "${CYAN}│${NC} %-8s: %-37s${CYAN}│${NC}\n" "Uptime" "$UPTIME"
    printf "${CYAN}│${NC} %-8s: %-37s${CYAN}│${NC}\n" "Users" "$USERS Account(s)"
    echo -e "${CYAN}├──────────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│${NC} [1] Create Account       [2] Create Trial      ${CYAN}│${NC}"
    echo -e "${CYAN}│${NC} [3] Renew Account        [4] Delete Account    ${CYAN}│${NC}"
    echo -e "${CYAN}│${NC} [0] Exit                                       ${CYAN}│${NC}"
    echo -e "${CYAN}└──────────────────────────────────────────────────┘${NC}"
    echo -ne " Select Option: "
    read opt
    case $opt in
        0) exit 0 ;;
        *) echo "Invalid Option"; sleep 1 ;;
    esac
}
while true; do show_menu; done
END_OF_MENU
chmod +x /usr/local/bin/menu

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
    
    echo -e "${GREEN}SUCCESS! Account Created.${NC}"
    echo -e "Domain  : $DOMAIN"
    echo -e "Pass    : $pass"
    echo -e "Expired : $exp_date"
    
    get_info
    TEXT="<code><b>✅ ACCOUNT SUCCESS CREATED</b>
━━━━━━━━━━━━━━━━━━━━
<b>Domain :</b> <code>${DOMAIN}</code>
<b>Pass   :</b> <code>${pass}</code>
<b>Exp    :</b> <code>${exp_date}</code>
━━━━━━━━━━━━━━━━━━━━
<i>By WINTUNELING VPN</i></code>"
    send_log "$TEXT"
    
    echo -e "Notification sent to Telegram."
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
    
    echo -e "${GREEN}SUCCESS! Trial Created.${NC}"
    echo -e "Domain  : $DOMAIN"
    echo -e "Pass    : $pass"
    echo -e "Expired : $mins Minutes"
    
    get_info
    TEXT="<code><b>⏳ TRIAL ACCOUNT CREATED</b>
━━━━━━━━━━━━━━━━━━━━
<b>Domain :</b> <code>${DOMAIN}</code>
<b>Pass   :</b> <code>${pass}</code>
<b>Exp    :</b> <code>${mins} Minutes</code>
━━━━━━━━━━━━━━━━━━━━
<i>By WINTUNELING VPN</i></code>"
    send_log "$TEXT"
    
    echo -e "Notification sent to Telegram."
    read -p "Press Enter..."
}

function delete_user() {
    clear
    echo -e "DELETE ACCOUNT LIST:"
    i=1
    while IFS=: read -r u p e; do
        printf "%-2s. %-15s (Exp: %s)\n" "$i" "$p" "$(date -d @$e +%F)"
        users[$i]=$u
        ((i++))
    done < $DB
    echo -ne "Select number (0 cancel): "
    read num
    if [[ "$num" == "0" ]]; then return; fi
    target=${users[$num]}
    if [ -n "$target" ]; then
        grep -v "^$target:" $DB > $DB.tmp && mv $DB.tmp $DB
        sync_config
        echo -e "${GREEN}Deleted $target${NC}"
    else
        echo -e "${RED}Invalid${NC}"
    fi
    read -p "Press Enter..."
}

function renew_user() {
    clear
    echo -e "RENEW ACCOUNT LIST:"
    i=1
    while IFS=: read -r u p e; do
        printf "%-2s. %-15s (Exp: %s)\n" "$i" "$p" "$(date -d @$e +%F)"
        users[$i]=$u
        ((i++))
    done < $DB
    echo -ne "Select number (0 cancel): "
    read num
    if [[ "$num" == "0" ]]; then return; fi
    target=${users[$num]}
    if [ -n "$target" ]; then
        read -p "Add Days: " d
        grep -v "^$target:" $DB > $DB.tmp
        line=$(grep "^$target:" $DB)
        old_pass=$(echo $line | cut -d: -f2)
        echo "$target:$old_pass:$(($(date +%s) + d * 86400))" >> $DB.tmp
        mv $DB.tmp $DB
        sync_config
        echo -e "${GREEN}Renewed $target${NC}"
    else
        echo -e "${RED}Invalid${NC}"
    fi
    read -p "Press Enter..."
}

function list_user() {
    clear
    echo -e "ACTIVE ACCOUNTS:"
    echo "-------------------------------------"
    while IFS=: read -r u p e; do
        printf "%-15s | %s\n" "$p" "$(date -d @$e +%F)"
    done < $DB
    echo "-------------------------------------"
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
    echo -e "1) Backup Now\n2) Restore from URL"
    read -p "Choice: " c
    if [ "$c" == "1" ]; then /usr/local/bin/backup-tg; echo "Done."; elif [ "$c" == "2" ]; then
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
    send_log "✅ Telegram Connected!"
    read -p "Press Enter..."
}

while true; do show_menu; done
END_OF_MENU

chmod +x $MENU_BIN

# LANDING PAGE
cat << 'EOF' > /usr/bin/landing-page
#!/bin/bash
CYAN='\033[0;36m'
NC='\033[0m'
DIR="/etc/zivpn"
DB="/etc/zivpn/user.db"
DOMAIN=$(openssl x509 -noout -subject -in $DIR/zivpn.crt 2>/dev/null | sed -n 's/^.*CN = //p')
[ -z "$DOMAIN" ] && DOMAIN="No Domain"
IP=$(curl -s ipv4.icanhazip.com)
CLIENT=$(cat /etc/wintunnel/client 2>/dev/null || echo "User")
UPTIME=$(uptime -p | sed 's/up //')
USERS=$(wc -l < $DB 2>/dev/null || echo "0")
clear
echo -e "${CYAN}┌──────────────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│${NC}                WINTUNELING VPN                  ${CYAN}│${NC}"
echo -e "${CYAN}├──────────────────────────────────────────────────┤${NC}"
printf "${CYAN}│${NC} %-8s: %-37s${CYAN}│${NC}\n" "IP" "$IP"
printf "${CYAN}│${NC} %-8s: %-37s${CYAN}│${NC}\n" "Domain" "${DOMAIN:0:30}"
printf "${CYAN}│${NC} %-8s: %-37s${CYAN}│${NC}\n" "Client" "${CLIENT:0:30}"
printf "${CYAN}│${NC} %-8s: %-37s${CYAN}│${NC}\n" "Uptime" "$UPTIME"
printf "${CYAN}│${NC} %-8s: %-37s${CYAN}│${NC}\n" "Users" "$USERS Active"
echo -e "${CYAN}└──────────────────────────────────────────────────┘${NC}"
echo -e ""
echo -e "${CYAN}      >>> PRESS [ ENTER ] TO ENTER MENU <<<${NC}"
read -n 1 -s -r -p ""
menu
EOF
chmod +x /usr/bin/landing-page


# FINISHING
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
echo -e "${YELLOW}        INSTALLATION SUCCESSFUL!         ${NC}"
echo -e "${GREEN}=========================================${NC}"
echo -e " Auto Backup : 00:00 (Midnight)"
echo -e " Command     : menu"
echo -e " Rebooting 5s..."
sleep 5
reboot
