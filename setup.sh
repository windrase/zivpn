#!/bin/bash
# WINTUNELING VPN - PROFESSIONAL EDITION

# GANTI IP INI DENGAN IP VPS ADMIN (BOT)
LICENSE_URL="http://129.226.206.227:3000/whitelist"

# CONFIG
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

# COLORS
RED='\e[1;31m'
GREEN='\e[1;32m'
YELLOW='\e[1;33m'
BLUE='\e[1;34m'
PURPLE='\e[1;35m'
CYAN='\e[1;36m'
WHITE='\e[1;37m'
NC='\e[0m'
BOLD='\e[1m'
GRAY='\e[90m'

# 1. CEK LICENSE
clear
echo -e "${YELLOW}[INFO] Checking License...${NC}"
MYIP=$(curl -s ipv4.icanhazip.com)
LICENSE_DATA=$(curl -s --connect-timeout 5 "$LICENSE_URL")

if echo "$LICENSE_DATA" | grep -q "$MYIP"; then
    CLIENT_DATA=$(echo "$LICENSE_DATA" | grep "$MYIP")
    CLIENT_NAME=$(echo "$CLIENT_DATA" | cut -d: -f2)
    EXP_DATE=$(echo "$CLIENT_DATA" | cut -d: -f3)
    TODAY=$(date +%Y-%m-%d)
    
    if [[ "$TODAY" > "$EXP_DATE" ]]; then
        echo -e "${RED}LICENSE EXPIRED ($EXP_DATE)${NC}"
        echo -e "Contact Admin: t.me/WINTUNELINGVPNN"
        exit 1
    else
        echo -e "${GREEN}License Valid! Welcome $CLIENT_NAME${NC}"
        mkdir -p /etc/wintunnel
        echo "$CLIENT_NAME" > /etc/wintunnel/client
        echo "$EXP_DATE" > /etc/wintunnel/exp
        sleep 2
    fi
else
    echo -e "${RED}IP NOT REGISTERED${NC}"
    exit 1
fi

# 2. SYSTEM PREP
clear
echo -e "${CYAN}[1/7] Preparing System...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y >/dev/null 2>&1
apt-get install -y curl wget jq openssl zip unzip cron net-tools lsb-release gnupg vnstat bc >/dev/null 2>&1

systemctl enable vnstat
systemctl start vnstat
INTF=$(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1)
sed -i "s/Interface \".*\"/Interface \"$INTF\"/g" /etc/vnstat.conf
systemctl restart vnstat

if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash - >/dev/null 2>&1
    apt-get install -y nodejs >/dev/null 2>&1
fi

# 3. INSTALL CORE
echo -e "${CYAN}[2/7] Installing Core...${NC}"
systemctl stop $SERVICE_VPN >/dev/null 2>&1
mkdir -p $DIR

# DOMAIN SETUP
clear
echo -e "${CYAN}DOMAIN CONFIGURATION${NC}"
echo -e "Input your domain/subdomain pointed to: $MYIP"
echo -e ""
while true; do
    read -p "Domain : " DOMAIN_INPUT
    if [ -z "$DOMAIN_INPUT" ]; then
        echo -e "${RED}Domain cannot be empty!${NC}"
    else
        echo -e "${GREEN}Domain set to: $DOMAIN_INPUT${NC}"
        break
    fi
done
sleep 1

ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
    wget -q https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64 -O $BIN
elif [[ "$ARCH" == "aarch64" ]]; then
    wget -q https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-arm64 -O $BIN
else
    echo -e "${RED}CPU Not Supported${NC}"
    exit 1
fi
chmod +x $BIN

openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
    -subj "/C=ID/ST=VPN/L=VPN/O=WINTUNNELING/CN=$DOMAIN_INPUT" \
    -keyout "$DIR/zivpn.key" -out "$DIR/zivpn.crt" >/dev/null 2>&1

if [ ! -f "$CONFIG" ]; then
cat <<EOF > $CONFIG
{
  "listen": ":5667",
  "cert": "$DIR/zivpn.crt",
  "key": "$DIR/zivpn.key",
  "obfs": "zivpn",
  "auth": {
    "mode": "passwords",
    "config": ["default"]
  }
}
EOF
fi
touch $DB

cat <<EOF > /etc/systemd/system/$SERVICE_VPN
[Unit]
Description=WINTUNELING VPN Core
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

# 4. INSTALL API BACKEND
echo -e "${CYAN}[3/7] Installing API Backend...${NC}"
mkdir -p $DIR_API
cd $DIR_API
if [ ! -f "package.json" ]; then
    npm init -y > /dev/null 2>&1
    npm install express shelljs body-parser > /dev/null 2>&1
fi
if [ ! -f "$API_KEY_FILE" ]; then openssl rand -hex 16 > $API_KEY_FILE; fi

cat << 'EOF' > server.js
const express = require('express');
const shell = require('shelljs');
const fs = require('fs');
const app = express();
const port = 5888;
const DB_FILE = '/etc/zivpn/user.db';
const CONFIG_FILE = '/etc/zivpn/config.json';
const API_KEY_FILE = '/etc/zivpn/apikey';

app.use(express.urlencoded({ extended: true }));
app.use(express.json());

const checkAuth = (req, res, next) => {
    const auth = req.query.auth || req.body.auth;
    let validKey = '';
    try { validKey = fs.readFileSync(API_KEY_FILE, 'utf8').trim(); } catch (e) {}
    if (auth === validKey && validKey !== '') next();
    else res.json({ status: 'error', message: 'API Key Invalid' });
};

function syncConfig() { shell.exec('systemctl restart zivpn'); }

app.get('/create/zivpn', checkAuth, (req, res) => {
    const { password, exp } = req.query;
    const username = req.query.user || req.query.username || password; 
    if(!username || !password) return res.json({status: 'error', message: 'Params missing'});

    const expDate = Math.floor(Date.now()/1000) + (parseInt(exp||30)*86400);
    const grep = shell.exec(`grep "^${username}:" ${DB_FILE}`, {silent:true});
    if (grep.stdout) return res.json({ status: 'error', message: 'User exists' });

    fs.appendFileSync(DB_FILE, `${username}:${password}:${expDate}\n`);
    
    let domain = shell.exec(`openssl x509 -noout -subject -in /etc/zivpn/zivpn.crt | sed -n 's/^.*CN = //p'`, {silent:true}).stdout.trim();
    if(!domain) domain = shell.exec('curl -s ipv4.icanhazip.com', {silent:true}).stdout.trim();

    try {
        const dbLines = fs.readFileSync(DB_FILE, 'utf8').split('\n').filter(l => l.trim());
        const configData = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
        configData.auth.config = dbLines.map(l => l.split(':')[1]);
        fs.writeFileSync(CONFIG_FILE, JSON.stringify(configData, null, 2));
        syncConfig();
        res.json({ status: 'success', message: `Account Created\nDomain: ${domain}\nUser: ${username}\nPass: ${password}\nExp: ${exp} Days` });
    } catch(e) { res.json({ status: 'error', message: 'Config Error' }); }
});

app.get('/trial/zivpn', checkAuth, (req, res) => {
    const user = "trial" + Math.floor(Math.random() * 10000);
    const pass = user;
    const expMin = req.query.exp || 60; 
    const expDate = Math.floor(Date.now()/1000) + (parseInt(expMin)*60);
    fs.appendFileSync(DB_FILE, `${user}:${pass}:${expDate}\n`);
    let domain = shell.exec(`openssl x509 -noout -subject -in /etc/zivpn/zivpn.crt | sed -n 's/^.*CN = //p'`, {silent:true}).stdout.trim();
    if(!domain) domain = shell.exec('curl -s ipv4.icanhazip.com', {silent:true}).stdout.trim();
    const dbLines = fs.readFileSync(DB_FILE, 'utf8').split('\n').filter(l => l.trim());
    const configData = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
    configData.auth.config = dbLines.map(l => l.split(':')[1]);
    fs.writeFileSync(CONFIG_FILE, JSON.stringify(configData, null, 2));
    syncConfig();
    res.json({ status: 'success', message: `Trial Created\nDomain: ${domain}\nUser: ${user}\nPass: ${pass}\nExp: ${expMin} Min` });
});

app.get('/renew/zivpn', checkAuth, (req, res) => {
    const target = req.query.password || req.query.user; 
    const addDays = req.query.exp || 30;
    let content = fs.readFileSync(DB_FILE, 'utf8').split('\n');
    let found = false, newContent = [];
    content.forEach(line => {
        if(!line.trim()) return;
        let [u, p, e] = line.split(':');
        if(u === target || p === target) {
            found = true;
            let now = Math.floor(Date.now()/1000);
            let nextExp = (parseInt(e) > now ? parseInt(e) : now) + (parseInt(addDays)*86400);
            newContent.push(`${u}:${p}:${nextExp}`);
        } else { newContent.push(line); }
    });
    if(!found) return res.json({status: 'error', message: 'User not found'});
    fs.writeFileSync(DB_FILE, newContent.join('\n') + '\n');
    syncConfig();
    res.json({status: 'success', message: 'Renew success'});
});

app.get('/delete/zivpn', checkAuth, (req, res) => {
    const target = req.query.password || req.query.user; 
    let content = fs.readFileSync(DB_FILE, 'utf8').split('\n'), newContent = [], found = false;
    content.forEach(line => {
        if(!line.trim()) return;
        let [u, p, e] = line.split(':');
        if(u === target || p === target) found = true; else newContent.push(line);
    });
    if(!found) return res.json({status: 'error', message: 'User not found'});
    fs.writeFileSync(DB_FILE, newContent.join('\n') + '\n');
    const configData = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
    configData.auth.config = newContent.map(l => l.split(':')[1]);
    fs.writeFileSync(CONFIG_FILE, JSON.stringify(configData, null, 2));
    syncConfig();
    res.json({status: 'success', message: 'Deleted success'});
});
app.listen(port, () => console.log(`API running on ${port}`));
EOF

cat <<EOF > /etc/systemd/system/$SERVICE_API
[Unit]
Description=UDPZIVPN API
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

# 5. FIREWALL & CRON
echo -e "${CYAN}[4/7] Configuring Firewall & Cron...${NC}"
iptables -t nat -A PREROUTING -i $INTF -p udp --dport 6000:19999 -j DNAT --to-destination :5667

cat <<EOF > /usr/local/bin/zivpn-expire
#!/bin/bash
DB="/etc/zivpn/user.db"
CONFIG="/etc/zivpn/config.json"
NOW=\$(date +%s); CHANGED=0; TMP_DB=\$(mktemp)
while IFS=: read -r user pass exp; do
    if [ \$exp -gt \$NOW ]; then echo "\$user:\$pass:\$exp" >> \$TMP_DB; else CHANGED=1; fi
done < \$DB
mv \$TMP_DB \$DB
if [ \$CHANGED -eq 1 ]; then
    PASS_LIST=\$(awk -F: '{printf "\"%s\",", \$2}' \$DB | sed 's/,\$//')
    [ -z "\$PASS_LIST" ] && PASS_LIST="\"default\""
    jq ".auth.config = [\$PASS_LIST]" \$CONFIG > \$CONFIG.tmp && mv \$CONFIG.tmp \$CONFIG
    systemctl restart zivpn
fi
EOF
chmod +x /usr/local/bin/zivpn-expire
(crontab -l 2>/dev/null; echo "* * * * * /usr/local/bin/zivpn-expire") | crontab - -u root 2>/dev/null

# 6. INSTALL BACKUP SCRIPT
echo -e "${CYAN}[5/7] Installing Backup Script...${NC}"
cat << 'EOF' > $BACKUP_BIN
#!/bin/bash
TG_CONFIG="/etc/zivpn/tg_backup.conf"
if [ ! -f "$TG_CONFIG" ]; then exit 0; fi
source $TG_CONFIG

DATE=$(date +%Y-%m-%d)
TIME=$(date +%H:%M:%S)
ISP=$(curl -s ip-api.com/json | jq -r .isp)
CITY=$(curl -s ip-api.com/json | jq -r .city)
IP=$(curl -s ipv4.icanhazip.com)
FILENAME="backup-$IP-$DATE.zip"

cd /root
zip -r $FILENAME /etc/zivpn/user.db /etc/zivpn/config.json /etc/zivpn/apikey /etc/zivpn/zivpn.crt /etc/zivpn/zivpn.key > /dev/null 2>&1

CAPTION="🤖 *AUTO BACKUP FILE*
━━━━━━━━━━━━━━━━━━━━
📅 Date  : \`$DATE\`
⏰ Time  : \`$TIME\`
🌐 IP    : \`$IP\`
🏢 ISP   : \`$ISP\`
🏙️ City  : \`$CITY\`
━━━━━━━━━━━━━━━━━━━━"

curl -F chat_id="$TG_ID" -F document=@"$FILENAME" -F caption="$CAPTION" -F parse_mode="Markdown" "https://api.telegram.org/bot$TG_TOKEN/sendDocument" > /dev/null 2>&1
rm $FILENAME
EOF
chmod +x $BACKUP_BIN

# 7. MENU PREMIUM
echo -e "${CYAN}[6/7] Installing Script Menu...${NC}"

cat << 'END_OF_MENU' > $MENU_BIN
#!/bin/bash
# WINTUNELING VPN MENU

DIR="/etc/zivpn"
DB="$DIR/user.db"
CONFIG="$DIR/config.json"
API_KEY_FILE="$DIR/apikey"
TG_CONFIG="$DIR/tg_backup.conf"
SERVICE="zivpn"

RED='\e[1;31m'
GREEN='\e[1;32m'
YELLOW='\e[1;33m'
BLUE='\e[1;34m'
PURPLE='\e[1;35m'
CYAN='\e[1;36m'
WHITE='\e[1;37m'
NC='\e[0m'
BOLD='\e[1m'
GRAY='\e[90m'

function get_info() {
    OS_FULL=$(lsb_release -d | cut -f2 | tr -d '"' | sed 's/Ubuntu //')
    ISP_FULL=$(curl -s ip-api.com/json | jq -r .isp)
    IP=$(curl -s ipv4.icanhazip.com)
    CLIENT_FULL=$(cat /etc/wintunnel/client 2>/dev/null || echo "Unknown")
    EXP_DATE=$(cat /etc/wintunnel/exp 2>/dev/null || echo "Unknown")
    DOMAIN_FULL=$(openssl x509 -noout -subject -in $DIR/zivpn.crt | sed -n 's/^.*CN = //p')
    [ -z "$DOMAIN_FULL" ] && DOMAIN_FULL="$IP"
    
    OS="${OS_FULL:0:18}"
    ISP="${ISP_FULL:0:18}"
    CLIENT="${CLIENT_FULL:0:25}"
    DOMAIN="${DOMAIN_FULL:0:25}"
    
    d1=$(date -d "$EXP_DATE" +%s 2>/dev/null)
    d2=$(date -d "$(date +%Y-%m-%d)" +%s)
    if [[ ! -z "$d1" ]]; then
        DAYS_LEFT=$(( ($d1 - $d2) / 86400 ))
        if [ $DAYS_LEFT -lt 0 ]; then DAYS_LEFT="EXPIRED"; fi
    else
        DAYS_LEFT="-"
    fi

    total_ram=$(free -m | awk 'NR==2{print $2}')
    used_ram=$(free -m | awk 'NR==2{print $3}')
    ram_perc=$(awk "BEGIN {printf \"%.0f\", $used_ram/$total_ram*100}")
    
    if systemctl is-active --quiet $SERVICE; then STATUS="${GREEN}ACTIVE${NC}"; else STATUS="${RED}DOWN${NC}"; fi
    API_KEY=$(cat $API_KEY_FILE)
    if [ -n "$API_KEY" ]; then API_STAT="${GREEN}ON${NC}"; else API_STAT="${RED}OFF${NC}"; fi
    RAM_TXT="$ram_perc% ($used_ram MB)"
    RAM_FIX="${RAM_TXT:0:18}"
}

function show_menu() {
    clear
    get_info
    echo -e "${CYAN} ┌──────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN} │${WHITE}${BOLD}                    WINTUNELING ZIVPN                     ${NC}${CYAN}│${NC}"
    echo -e "${CYAN} ├──────────────────────[ SYSTEM INFO ]─────────────────────┤${NC}"
    printf "${CYAN} │${NC} ${GRAY}OS   :${NC} %-18s ${GRAY}RAM  :${NC} %-18s     ${CYAN}│${NC}\n" "$OS" "$RAM_FIX"
    printf "${CYAN} │${NC} ${GRAY}IP   :${NC} %-18s ${GRAY}ISP  :${NC} %-18s     ${CYAN}│${NC}\n" "$IP" "$ISP"
    echo -e "${CYAN} ├────────────────────────[ LICENSE ]───────────────────────┤${NC}"
    printf "${CYAN} │${NC} ${GRAY}Client  :${NC} ${YELLOW}%-35s${NC}           ${CYAN}│${NC}\n" "$CLIENT"
    printf "${CYAN} │${NC} ${GRAY}Expired :${NC} ${WHITE}%-12s${NC} (${GREEN}%-4s Hari${NC})                ${CYAN}│${NC}\n" "$EXP_DATE" "$DAYS_LEFT"
    echo -e "${CYAN} ├──────────────────────[ VPN STATUS ]──────────────────────┤${NC}"
    printf "${CYAN} │${NC} ${GRAY}Domain  :${NC} ${GREEN}%-35s${NC}           ${CYAN}│${NC}\n" "$DOMAIN"
    printf "${CYAN} │${NC} ${GRAY}Status  :${NC} %-14s ${GRAY}API Key :${NC} %-14s   ${CYAN}│${NC}\n" "$STATUS" "$API_STAT"
    echo -e "${CYAN} └──────────────────────────────────────────────────────────┘${NC}"
    echo -e ""
    echo -e " ${CYAN}[ MENU UTAMA ]${NC}"
    printf " ${WHITE}[1]${NC} %-26s ${WHITE}[2]${NC} %-26s\n" "Create Account" "Create Trial"
    printf " ${WHITE}[3]${NC} %-26s ${WHITE}[4]${NC} %-26s\n" "Renew Account" "Delete Account"
    printf " ${WHITE}[5]${NC} %-26s ${WHITE}[6]${NC} %-26s\n" "List Users" "Change Domain"
    echo -e ""
    echo -e " ${CYAN}[ SETTINGS ]${NC}"
    printf " ${WHITE}[7]${NC} %-26s ${WHITE}[8]${NC} %-26s\n" "Restart Service" "Setup Telegram"
    printf " ${WHITE}[9]${NC} %-26s ${WHITE}[10]${NC} %-25s\n" "Backup Now" "Auto Backup"
    printf " ${WHITE}[11]${NC} %-49s\n" "Restore Data"
    echo -e ""
    echo -e "                         ${RED}[0] Exit${NC}"
    echo -e "${CYAN} ────────────────────────────────────────────────────────────${NC}"
    read -p " Select Option: " opt
    case $opt in
        1) create_user ;;
        2) trial_user ;;
        3) renew_user ;;
        4) delete_user ;;
        5) list_user ;;
        6) change_domain ;;
        7) systemctl restart $SERVICE; echo -e "${GREEN}Service Restarted.${NC}"; sleep 1 ;;
        8) setup_telegram_notif ;;
        9) backup_data ;;
        10) auto_backup_setup ;;
        11) restore_data ;;
        0) exit 0 ;;
    esac
}

function sync_config() {
    PASS_LIST=$(awk -F: '{printf "\"%s\",", $2}' $DB | sed 's/,$//')
    [ -z "$PASS_LIST" ] && PASS_LIST="\"default\""
    jq ".auth.config = [$PASS_LIST]" $CONFIG > $CONFIG.tmp && mv $CONFIG.tmp $CONFIG
    systemctl restart $SERVICE
}

function create_user() {
    echo -e "\n${CYAN}┌── [ CREATE ACCOUNT ]${NC}"
    read -p "│ Password : " pass
    user=$pass 
    if grep -q "^$user:" $DB; then echo -e "│ ${RED}Account Exists!${NC}"; read -p "└ Enter..."; return; fi
    read -p "│ Active Days  : " days
    exp=$(($(date +%s) + days * 86400))
    echo "$user:$pass:$exp" >> $DB
    sync_config
    echo -e "│\n│ ${GREEN}SUCCESS! Account Created.${NC}"
    echo -e "│ Domain : $DOMAIN"
    echo -e "│ Password: $pass"
    echo -e "│ Expired: $(date -d @$exp "+%d %b %Y")"
    echo -e "${CYAN}└─────────────────────────${NC}"
    read -p "Press Enter..."
}

function trial_user() {
    echo -e "\n${CYAN}┌── [ TRIAL ACCOUNT ]${NC}"
    read -p "│ Duration (Min): " mins
    user="trial$(date +%s | tail -c 4)"
    pass=$user
    exp=$(($(date +%s) + mins * 60))
    echo "$user:$pass:$exp" >> $DB
    sync_config
    echo -e "│\n│ ${GREEN}SUCCESS! Trial Created.${NC}"
    echo -e "│ Domain : $DOMAIN"
    echo -e "│ Password: $pass"
    echo -e "│ Expired: $mins Minutes"
    echo -e "${CYAN}└─────────────────────────${NC}"
    read -p "Press Enter..."
}

function delete_user() {
    clear
    echo -e "${CYAN} ┌──────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN} │${WHITE}                 DELETE ACCOUNT                   ${NC}${CYAN}│${NC}"
    echo -e "${CYAN} ├──────┬────────────────────────┬──────────────────┤${NC}"
    echo -e "${CYAN} │${WHITE}  NO  ${NC}${CYAN}│${WHITE}        PASSWORD        ${NC}${CYAN}│${WHITE}     EXPIRED      ${NC}${CYAN}│${NC}"
    echo -e "${CYAN} ├──────┼────────────────────────┼──────────────────┤${NC}"
    i=1
    while IFS=: read -r user pass exp; do
        exp_date=$(date -d @$exp "+%d-%m-%Y")
        printf "${CYAN} │ ${WHITE}%-4s ${CYAN}│ ${YELLOW}%-22s ${CYAN}│ ${GREEN}%-16s ${CYAN}│${NC}\n" "$i" "$pass" "$exp_date"
        user_list[$i]="$user"
        ((i++))
    done < $DB
    echo -e "${CYAN} └──────┴────────────────────────┴──────────────────┘${NC}"
    echo -e " ${RED}[0] Cancel${NC}"
    read -p " Pilih Nomor Untuk Hapus: " num
    if [[ "$num" == "0" || -z "${user_list[$num]}" ]]; then return; fi
    target="${user_list[$num]}"
    grep -v "^$target:" $DB > $DB.tmp && mv $DB.tmp $DB
    sync_config
    echo -e "${GREEN}Account Deleted Successfully.${NC}"
    read -p "Press Enter..."
}

function list_user() {
    clear
    echo -e "${CYAN} ┌──────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN} │${WHITE}                 LIST ACCOUNTS                    ${NC}${CYAN}│${NC}"
    echo -e "${CYAN} ├────────────────────────┬─────────────────────────┤${NC}"
    echo -e "${CYAN} │${WHITE}        PASSWORD        ${NC}${CYAN}│${WHITE}       EXPIRED       ${NC}${CYAN}│${NC}"
    echo -e "${CYAN} ├────────────────────────┼─────────────────────────┤${NC}"
    while IFS=: read -r user pass exp; do
        exp_date=$(date -d @$exp "+%d-%m-%Y")
        printf "${CYAN} │${YELLOW} %-22s ${CYAN}│${GREEN} %-23s ${CYAN}│${NC}\n" "$pass" "$exp_date"
    done < $DB
    echo -e "${CYAN} └────────────────────────┴─────────────────────────┘${NC}"
    read -p " Press Enter to return..."
}

function renew_user() {
    clear
    echo -e "${CYAN} ┌──────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN} │${WHITE}                 RENEW ACCOUNT                    ${NC}${CYAN}│${NC}"
    echo -e "${CYAN} ├──────┬────────────────────────┬──────────────────┤${NC}"
    echo -e "${CYAN} │${WHITE}  NO  ${NC}${CYAN}│${WHITE}        PASSWORD        ${NC}${CYAN}│${WHITE}     EXPIRED      ${NC}${CYAN}│${NC}"
    echo -e "${CYAN} ├──────┼────────────────────────┼──────────────────┤${NC}"
    i=1
    while IFS=: read -r user pass exp; do
        exp_date=$(date -d @$exp "+%d-%m-%Y")
        printf "${CYAN} │ ${WHITE}%-4s ${CYAN}│ ${YELLOW}%-22s ${CYAN}│ ${GREEN}%-16s ${CYAN}│${NC}\n" "$i" "$pass" "$exp_date"
        user_list[$i]="$user"
        ((i++))
    done < $DB
    echo -e "${CYAN} └──────┴────────────────────────┴──────────────────┘${NC}"
    read -p " Select Number to Renew: " num
    if [[ -z "${user_list[$num]}" ]]; then return; fi
    target="${user_list[$num]}"
    read -p " Add Days: " days
    TMP=$(mktemp)
    while IFS=: read -r u p e; do
        if [ "$u" == "$target" ]; then
            now=$(date +%s); [ $e -lt $now ] && new_exp=$now || new_exp=$e
            final_exp=$((new_exp + days * 86400))
            echo "$u:$p:$final_exp" >> $TMP
            renew_date=$(date -d @$final_exp "+%d-%m-%Y")
        else echo "$u:$p:$e" >> $TMP; fi
    done < $DB
    mv $TMP $DB; sync_config
    echo -e "${GREEN}Renew Success. New Expired: $renew_date${NC}"
    read -p "Enter..."
}

function change_domain() {
    echo -e "\n${CYAN}[ CHANGE DOMAIN ]${NC}"
    read -p "New Domain: " d
    openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 -subj "/C=ID/CN=$d" -keyout $DIR/zivpn.key -out $DIR/zivpn.crt >/dev/null 2>&1
    systemctl restart $SERVICE; echo -e "${GREEN}Updated to $d${NC}"; read -p "Enter..."
}

function setup_telegram_notif() {
    clear
    echo -e "${CYAN}[ SETUP TELEGRAM NOTIFICATION ]${NC}"
    if [ -f "$TG_CONFIG" ]; then
        echo -e "${GREEN}Telegram sudah terkonfigurasi.${NC}"
        read -p "Ingin konfigurasi ulang? [y/n]: " ans
        if [[ "$ans" == "y" ]]; then rm "$TG_CONFIG"; else return; fi
    fi
    echo -e "${YELLOW}Masukkan Data Bot Telegram Anda:${NC}"
    read -p "Bot Token : " token
    read -p "Chat ID   : " chatid
    if [[ -z "$token" || -z "$chatid" ]]; then
        echo -e "${RED}Gagal! Data tidak boleh kosong.${NC}"
    else
        echo "TG_TOKEN='$token'" > $TG_CONFIG
        echo "TG_ID='$chatid'" >> $TG_CONFIG
        echo -e "${GREEN}✅ Konfigurasi Telegram Disimpan!${NC}"
    fi
    read -p "Press Enter..."
}

function backup_data() {
    clear
    echo -e "${CYAN}[ BACKUP DATA TO TELEGRAM ]${NC}"
    if [ ! -f "$TG_CONFIG" ]; then
        echo -e "${RED}Telegram belum disetup!${NC}"
        echo -e "Silakan pilih menu [8] Setup Telegram terlebih dahulu."
        read -p "Press Enter..."
        return
    fi
    echo -e "${YELLOW}Sending Backup...${NC}"
    /usr/local/bin/backup-tg
    echo -e "${GREEN}✅ Done! Check your Telegram.${NC}"
    read -p "Press Enter..."
}

function auto_backup_setup() {
    clear
    echo -e "${CYAN}[ AUTO BACKUP SETTING ]${NC}"
    if [ ! -f "$TG_CONFIG" ]; then
        echo -e "${RED}Telegram belum disetup!${NC}"; read -p "Enter..."; return
    fi
    read -p "Set Jam (Format HH:MM, ex: 00:00) : " jam
    if [[ ! $jam =~ ^[0-9][0-9]:[0-9][0-9]$ ]]; then
        echo -e "${RED}Format Salah!${NC}"; read -p "Enter..."; return
    fi
    hh=$(echo $jam | cut -d: -f1)
    mm=$(echo $jam | cut -d: -f2)
    echo "$mm $hh * * * root /usr/local/bin/backup-tg" > /etc/cron.d/zivpn_autobackup
    service cron restart
    echo -e "${GREEN}✅ Auto Backup Diatur pada jam $jam${NC}"
    read -p "Press Enter..."
}

function restore_data() {
    clear; echo -e "${CYAN}[ RESTORE DATA ]${NC}"
    read -p "Link File Backup : " url
    if [ -z "$url" ]; then echo -e "${RED}URL Kosong!${NC}"; sleep 1; return; fi
    wget -O /root/backup.zip "$url" > /dev/null 2>&1
    if [ -f /root/backup.zip ]; then
        unzip -o /root/backup.zip -d / > /dev/null 2>&1
        rm /root/backup.zip
        systemctl restart $SERVICE
        echo -e "${GREEN}✅ Data Restored!${NC}"
    else
        echo -e "${RED}❌ Failed Download!${NC}"
    fi
    read -p "Enter..."
}

while true; do show_menu; done
END_OF_MENU

chmod +x $MENU_BIN

# 8. FINISHING
systemctl daemon-reload
systemctl enable $SERVICE_VPN $SERVICE_API
systemctl start $SERVICE_VPN
systemctl start $SERVICE_API
API_KEY=$(cat $API_KEY_FILE)
MYIP=$(curl -s ipv4.icanhazip.com)

clear
echo -e "${GREEN}=========================================${NC}"
echo -e "${YELLOW}    WINTUNELING VPN INSTALLED SUCCESS    ${NC}"
echo -e "${GREEN}=========================================${NC}"
echo -e " Command  : ${BOLD}menu${NC}"
echo -e " IP VPS   : ${CYAN}$MYIP${NC}"
echo -e " API Port : ${CYAN}5888${NC}"
echo -e " API Key  : ${YELLOW}$API_KEY${NC}"
echo -e "${GREEN}=========================================${NC}"
echo -e "${YELLOW}Rebooting System in 5 seconds...${NC}"
sleep 5
reboot
