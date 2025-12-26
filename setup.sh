#!/bin/bash
# WINTUNELING VPN - FINAL ULTIMATE
# Features: ZIVPN Core, API Telegram, Password Only, Minimalist UI (List/Renew/Del)

# ==========================================
# 0. FIX PROFILE & PERMISSIONS
# ==========================================
cat > /root/.profile << 'EOF'
if [ "$BASH" ]; then
  if [ -f ~/.bashrc ]; then
    . ~/.bashrc
  fi
fi
mesg n 2>/dev/null || true
EOF

# ==========================================
# 1. CONFIGURATION
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
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
PURPLE='\033[0;35m'
BLUE='\033[0;34m'
WHITE='\033[1;37m'
NC='\033[0m'

# ==========================================
# 2. LICENSE CHECK
# ==========================================
clear
echo -e "${YELLOW}[INFO] Checking License...${NC}"
MYIP=$(curl -s ipv4.icanhazip.com)
LICENSE_DATA=$(curl -s --connect-timeout 5 "$LICENSE_URL")

if echo "$LICENSE_DATA" | grep -q "$MYIP"; then
    DATA_CLIENT=$(echo "$LICENSE_DATA" | grep "$MYIP")
    CLIENT_NAME=$(echo "$DATA_CLIENT" | cut -d: -f2)
    EXP_DATE=$(echo "$DATA_CLIENT" | cut -d: -f3)
    TODAY=$(date +%Y-%m-%d)
    if [[ "$TODAY" > "$EXP_DATE" ]]; then
        echo -e "${GREEN}┌──────────────────────────────────────────────────┐${NC}"
        echo -e "${RED}            ⛔ LICENSE EXPIRED: $EXP_DATE${NC}"; exit 1
        echo -e "${RED}     Please Contact t.me/WINTUNELING VPN For License${NC}"
        echo -e "${GREEN}└──────────────────────────────────────────────────┘${NC}"
    else
        echo -e "${PURPLE}┌──────────────────────────────────────────────────┐${NC}"
        echo -e "${GREEN}             ✅ LICENSE ACTIVE! ($CLIENT_NAME)${NC}"
        echo -e "${GREEN}           THANKS FOR USING THIS SCRIPT${NC}"
        echo -e "${PURPLE}└──────────────────────────────────────────────────┘${NC}"
        mkdir -p /etc/wintunnel
        echo "$CLIENT_NAME" > /etc/wintunnel/client
        echo "$EXP_DATE" > /etc/wintunnel/exp
        sleep 1
    fi
else
    echo -e "${RED}⛔ ACCESS DENIED!${NC}"; exit 1
fi

# ==========================================
# 3. SYSTEM PREPARATION
# ==========================================
echo -e "${CYAN}[1/5] System Setup...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y >/dev/null 2>&1
apt-get install -y curl wget jq openssl zip unzip cron net-tools lsb-release gnupg vnstat bc neofetch iptables-persistent >/dev/null 2>&1

systemctl enable vnstat; systemctl start vnstat
INTF=$(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1)
sed -i "s/Interface \".*\"/Interface \"$INTF\"/g" /etc/vnstat.conf
systemctl restart vnstat

if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash - >/dev/null 2>&1
    apt-get install -y nodejs >/dev/null 2>&1
fi

echo -e "${CYAN}[2/5] Installing Core...${NC}"
systemctl stop $SERVICE_VPN >/dev/null 2>&1
mkdir -p $DIR $DIR_API

# --- DOMAIN SETUP ---
clear
echo -e "${GREEN}┌──────────────────────────────────────────────────┐${NC}"
echo -e "${YELLOW}│             ISI DOMAIN SERVER ANDA               ${NC}"
echo -e "${GREEN}└──────────────────────────────────────────────────┘${NC}"
while true; do
    read -p "Input Domain (e.g., vpn.myserver.com): " DOMAIN_INPUT
    if [ -n "$DOMAIN_INPUT" ]; then
        echo -e "${GREEN}Domain saved: $DOMAIN_INPUT${NC}"
        mkdir -p /etc/xray
        echo "$DOMAIN_INPUT" > /etc/xray/domain
        break
    else
        echo -e "${RED}Error:DOMAIN TIDAK BOLEH KOSONG!!!.${NC}"
    fi
done

ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
    wget -q https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64 -O $BIN
else
    wget -q https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-arm64 -O $BIN
fi
chmod +x $BIN

# CERTIFICATE GENERATOR
if [ ! -f "$DIR/zivpn.crt" ]; then
    openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 -subj "/C=ID/CN=$DOMAIN_INPUT" -keyout "$DIR/zivpn.key" -out "$DIR/zivpn.crt" >/dev/null 2>&1
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

# ==========================================
# API SETUP (FIX: PATH, NOTIF, PASS ONLY)
# ==========================================
if [ ! -f "$API_KEY_FILE" ]; then openssl rand -hex 3 > $API_KEY_FILE; fi
cd $DIR_API
if [ ! -f "package.json" ]; then npm init -y >/dev/null 2>&1; npm install express shelljs body-parser >/dev/null 2>&1; fi

cat << 'EOF' > server.js
const express = require('express');
const shell = require('shelljs');
const fs = require('fs');
const app = express();
const port = 5888;
const API_KEY_FILE = '/etc/zivpn/apikey';
const DB_FILE = '/etc/zivpn/user.db';
const CONFIG_FILE = '/etc/zivpn/config.json';
const TG_CONFIG_FILE = '/etc/zivpn/tg_backup.conf';
const SERVICE = 'zivpn';

app.use(express.urlencoded({ extended: true }));
app.use(express.json());

let SERVER_ISP = 'Unknown';
let SERVER_IP = 'Unknown';
let SERVER_DOMAIN = 'Unknown';

shell.exec('/usr/bin/curl -s ip-api.com/json', {silent:true}, (code, stdout) => {
    try {
        const d = JSON.parse(stdout);
        SERVER_ISP = d.isp;
        SERVER_IP = d.query;
    } catch (e) {}
});
try { SERVER_DOMAIN = fs.readFileSync('/etc/xray/domain', 'utf8').trim(); } catch(e) {}

function sendLog(message) {
    if (!fs.existsSync(TG_CONFIG_FILE)) return;
    try {
        const content = fs.readFileSync(TG_CONFIG_FILE, 'utf8');
        const tokenMatch = content.match(/TG_TOKEN='([^']+)'/);
        const idMatch = content.match(/TG_ID='([^']+)'/);
        if (tokenMatch && idMatch) {
            const token = tokenMatch[1];
            const id = idMatch[1];
            const cmd = `/usr/bin/curl -s -X POST "https://api.telegram.org/bot${token}/sendMessage" -d chat_id="${id}" -d parse_mode="html" --data-urlencode text="${message}" > /dev/null 2>&1`;
            shell.exec(cmd, {async:true, silent:true});
        }
    } catch (e) {}
}

const checkAuth = (req, res, next) => {
    let validKey = '';
    try { validKey = fs.readFileSync(API_KEY_FILE, 'utf8').trim(); } catch (e) {}
    const providedKey = req.query.auth || req.body.auth;
    if (providedKey === validKey && validKey !== '') next();
    else res.json({ status: 'error', message: 'Invalid API Key' });
};

function sync() {
    try {
        const data = fs.readFileSync(DB_FILE, 'utf8');
        const lines = data.split('\n').filter(line => line.trim() !== '');
        const passwords = lines.map(line => line.split(':')[1]).filter(p => p);
        const configData = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
        configData.auth.config = passwords.length > 0 ? passwords : ["default"];
        fs.writeFileSync(CONFIG_FILE, JSON.stringify(configData, null, 2));
        shell.exec(`systemctl restart ${SERVICE}`);
    } catch (e) {}
}

app.get('/create/zivpn', checkAuth, (req, res) => {
    const password = req.query.password;
    const expDays = parseInt(req.query.exp);
    if (!password || isNaN(expDays)) return res.json({ status: 'error', message: 'Missing parameters' });
    
    const dbData = fs.readFileSync(DB_FILE, 'utf8');
    if (dbData.includes(`:${password}:`)) return res.json({ status: 'error', message: 'Account exists' });
    
    const expDateMs = Date.now() + (expDays * 86400 * 1000);
    const expDateSec = Math.floor(expDateMs / 1000);
    fs.appendFileSync(DB_FILE, `${password}:${password}:${expDateSec}\n`);
    sync();

    const d = new Date(expDateMs);
    const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    const dateStr = `${d.getDate()} ${months[d.getMonth()]} ${d.getFullYear()}`;
    const msg = `CREATE AKUN ZIVPN (VIA BOT)\n┌────────────────────────┐\n│ Host : <code>${SERVER_DOMAIN}</code>\n│ IP : <code>${SERVER_IP}</code>\n│ ISP : <code>${SERVER_ISP}</code>\n│ Pass : <code>${password}</code>\n│ Expire : <code>${dateStr}</code>\n└────────────────────────┘`;
    sendLog(msg);
    res.json({ status: 'success', message: 'Account created' });
});

app.get('/trial/zivpn', checkAuth, (req, res) => {
    const expMins = parseInt(req.query.exp);
    if (isNaN(expMins)) return res.json({ status: 'error', message: 'Invalid exp' });
    const user = `trial${Math.floor(Math.random() * 10000)}`;
    const expDateMs = Date.now() + (expMins * 60 * 1000);
    const expDateSec = Math.floor(expDateMs / 1000);
    fs.appendFileSync(DB_FILE, `${user}:${user}:${expDateSec}\n`);
    sync();
    const msg = `CREATE TRIAL ZIVPN (VIA BOT)\n┌────────────────────────┐\n│ Host : <code>${SERVER_DOMAIN}</code>\n│ IP : <code>${SERVER_IP}</code>\n│ ISP : <code>${SERVER_ISP}</code>\n│ Pass : <code>${user}</code>\n│ Expire : <code>${expMins} Mins</code>\n└────────────────────────┘`;
    sendLog(msg);
    res.json({ status: 'success', message: 'Trial Created', data: { user: user, pass: user, exp: expMins } });
});

app.get('/renew/zivpn', checkAuth, (req, res) => {
    const password = req.query.password;
    const expDays = parseInt(req.query.exp);
    if (!password || isNaN(expDays)) return res.json({ status: 'error', message: 'Missing params' });
    let lines = fs.readFileSync(DB_FILE, 'utf8').split('\n');
    let found = false;
    let newLines = lines.map(line => {
        if (line.trim() === '') return null;
        const parts = line.split(':');
        if (parts[1] === password) { 
            found = true;
            const currentExp = parseInt(parts[2]);
            const now = Math.floor(Date.now() / 1000);
            const baseTime = (currentExp > now) ? currentExp : now;
            const newExp = baseTime + (expDays * 86400);
            return `${parts[0]}:${parts[1]}:${newExp}`;
        }
        return line;
    }).filter(l => l !== null);
    if (!found) return res.json({ status: 'error', message: 'Account not found' });
    fs.writeFileSync(DB_FILE, newLines.join('\n') + '\n');
    sync();
    sendLog(`RENEW AKUN ZIVPN (VIA BOT)\nPass: <code>${password}</code>\nAdd: ${expDays} Days`);
    res.json({ status: 'success', message: 'Renewed' });
});

app.get('/delete/zivpn', checkAuth, (req, res) => {
    const password = req.query.password; 
    if (!password) return res.json({ status: 'error', message: 'Missing params' });
    let lines = fs.readFileSync(DB_FILE, 'utf8').split('\n');
    let found = false;
    const newLines = lines.filter(line => {
        if (line.trim() === '') return false;
        const parts = line.split(':');
        if (parts[1] === password) { found = true; return false; }
        return true;
    });
    if (!found) return res.json({ status: 'error', message: 'Account not found' });
    fs.writeFileSync(DB_FILE, newLines.join('\n') + (newLines.length ? '\n' : ''));
    sync();
    sendLog(`DELETE AKUN ZIVPN (VIA BOT)\nPass: <code>${password}</code>`);
    res.json({ status: 'success', message: 'Deleted' });
});

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
Environment=PATH=/usr/bin:/usr/local/bin:/sbin:/bin
[Install]
WantedBy=multi-user.target
EOF

iptables -t nat -A PREROUTING -i $INTF -p udp --dport 6000:19999 -j DNAT --to-destination :5667
netfilter-persistent save >/dev/null 2>&1

# ==========================================
# 4. MENU SCRIPT (FINAL UI UPDATE)
# ==========================================
echo -e "${CYAN}[3/5] Installing Menu...${NC}"

cat << 'END_OF_MENU' > $MENU_BIN
#!/bin/bash
DIR="/etc/zivpn"
DB="$DIR/user.db"
CONFIG="$DIR/config.json"
API_KEY_FILE="$DIR/apikey"
TG_CONFIG="$DIR/tg_backup.conf"
SERVICE="zivpn"
SERVICE_API="zivpn-api"

# Colors
NC='\033[0m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'

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
    IP=$(curl -s ipv4.icanhazip.com)
    DOMAIN=$(openssl x509 -noout -subject -in $DIR/zivpn.crt 2>/dev/null | sed -n 's/^.*CN = //p')
    [ -z "$DOMAIN" ] && DOMAIN="No Domain"
    JSON_IP=$(curl -s ip-api.com/json)
    ISP=$(echo "$JSON_IP" | jq -r .isp)
    REGION=$(echo "$JSON_IP" | jq -r .regionName)
    CLIENT=$(cat /etc/wintunnel/client 2>/dev/null || echo "User")
    EXP_DATE=$(cat /etc/wintunnel/exp 2>/dev/null || echo "Lifetime")
    RAM_USED=$(free -m | awk 'NR==2{print $3}')
    RAM_TOTAL=$(free -m | awk 'NR==2{print $2}')
    RAM_PERC=$(awk "BEGIN {printf \"%.0f\", $RAM_USED/$RAM_TOTAL*100}")
    CPU_MODEL=$(lscpu | grep "Model name" | cut -d: -f2 | sed 's/^ //;s/  */ /g' | cut -c1-20)
    UPTIME=$(uptime -p | sed 's/up //')
    USERS=$(wc -l < $DB 2>/dev/null || echo "0")
    API_KEY=$(cat $API_KEY_FILE 2>/dev/null)
    if systemctl is-active --quiet $SERVICE; then STAT_VPN="${GREEN}ON${NC}"; else STAT_VPN="${RED}OFF${NC}"; fi
    if systemctl is-active --quiet $SERVICE_API; then STAT_API="${GREEN}ON${NC}"; else STAT_API="${RED}OFF${NC}"; fi
}

function show_menu() {
    clear
    get_info
    echo -e "${PURPLE} ╭────────────────────────────────────────────────${NC}"
    echo -e "${PURPLE} │${CYAN}                 WINTUNELING ZIVPN${NC}"
    echo -e "${PURPLE} ├────────────────────────────────────────────────${NC}"
    echo -e "${PURPLE} │${CYAN} OS      : ${YELLOW}$OS${NC}"
    echo -e "${PURPLE} │${CYAN} IP      : ${YELLOW}$IP${NC}"
    echo -e "${PURPLE} │${CYAN} Domain  : ${YELLOW}$DOMAIN${NC}"
    echo -e "${PURPLE} │${CYAN} ISP     : ${YELLOW}$ISP${NC}"
    echo -e "${PURPLE} ├─────────────────────────────────────────────────${NC}"
    echo -e "${PURPLE} │${CYAN} Client  : ${YELLOW}$CLIENT${NC}"
    echo -e "${PURPLE} │${CYAN} Exp     : ${YELLOW}$EXP_DATE${NC}"
    echo -e "${PURPLE} ├─────────────────────────────────────────────────${NC}"
    echo -e "${PURPLE} │${CYAN} RAM     : ${WHITE}$RAM_USED/$RAM_TOTAL MB ($RAM_PERC%)${NC}"
    echo -e "${PURPLE} │${CYAN} CPU     : ${WHITE}$CPU_MODEL${NC}"
    echo -e "${PURPLE} │${CYAN} Uptime  : ${WHITE}$UPTIME${NC}"
    echo -e "${PURPLE} │${CYAN} Users   : ${WHITE}$USERS Account(s)${NC}"
    echo -e "${PURPLE} ├─────────────────────────────────────────────────${NC}"
    echo -e "${PURPLE} │${CYAN} Service : ${STAT_VPN}    ${CYAN}API : ${STAT_API}${NC}"
    echo -e "${PURPLE} │${CYAN} API Key : ${YELLOW}$API_KEY${NC}"
    echo -e "${PURPLE} ╰─────────────────────────────────────────────────${NC}"
    echo -e ""
    echo -e "  ${BLUE}[1]${NC} Create Account        ${BLUE}[2]${NC} Create Trial"
    echo -e "  ${BLUE}[3]${NC} Renew Account         ${BLUE}[4]${NC} Delete Account"
    echo -e "  ${BLUE}[5]${NC} List Accounts         ${BLUE}[6]${NC} Change Domain"
    echo -e "  ${BLUE}[7]${NC} Backup/Restore        ${BLUE}[8]${NC} Setup Notif"
    echo -e "  ${BLUE}[9]${NC} Restart Service       ${BLUE}[10]${NC} Generate API"
    echo -e "  ${BLUE}[11]${NC} Cek Sertifikat        ${BLUE}[0]${NC} Exit"
    echo -e ""
    echo -ne "  ${YELLOW}Select Option : ${NC}"
    read opt
    case $opt in
        1) create_user ;; 2) trial_user ;; 3) renew_user ;; 4) delete_user ;;
        5) list_user ;; 6) change_domain ;; 7) backup_menu ;; 8) setup_telegram ;;
        9) systemctl restart $SERVICE; echo "Restarted."; sleep 1 ;; 
        10) generate_api ;; 11) clear; cat /etc/zivpn/zivpn.crt; echo ""; read -p "Enter..." ;;
        0) exit 0 ;;
        *) echo "Invalid"; sleep 1 ;;
    esac
}

function generate_api() {
    echo -e "\n${CYAN}[ GENERATE NEW API KEY ]${NC}"
    read -p "Are you sure? [y/n]: " answer
    if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
        NEW_KEY=$(openssl rand -hex 3)
        echo "$NEW_KEY" > "$API_KEY_FILE"
        echo -e "${GREEN}Success! New API Key: ${YELLOW}$NEW_KEY${NC}"
        sleep 2
    fi
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
    if grep -q "^$user:" $DB; then echo -e "${RED}Exists!${NC}"; sleep 1; return; fi
    read -p "Exp Days : " days
    exp=$(($(date +%s) + days * 86400))
    echo "$user:$pass:$exp" >> $DB
    sync_config
    exp_date=$(date -d @$exp "+%d %b %Y %H:%M")
    DOMAIN=$(cat /etc/xray/domain 2>/dev/null || curl -s ipv4.icanhazip.com)
    
    clear
    echo -e ""
    echo -e "${CYAN}CREATE AKUN ZIVPN${NC}"
    echo -e "${CYAN}┌────────────────────────┐${NC}"
    echo -e "${CYAN}│${NC} Host   : ${DOMAIN}"
    echo -e "${CYAN}│${NC} IP     : ${IP}"
    echo -e "${CYAN}│${NC} ISP    : ${ISP}"
    echo -e "${CYAN}│${NC} Pass   : ${pass}"
    echo -e "${CYAN}│${NC} Expire : ${exp_date}"
    echo -e "${CYAN}└────────────────────────┘${NC}"
    echo -e "Terima kasih telah menggunakan layanan kami"
    
    TEXT="CREATE AKUN ZIVPN
┌────────────────────────┐
│ Host   : <code>${DOMAIN}</code>
│ IP     : <code>${IP}</code>
│ ISP    : <code>${ISP}</code>
│ Pass   : <code>${pass}</code>
│ Expire : <code>${exp_date}</code>
└────────────────────────┘
Terima kasih telah menggunakan layanan kami"
    send_log "$TEXT"
    read -n 1 -s -r -p "Press [ Enter ] to back to menu"
}

function trial_user() {
    echo -e "\n${CYAN}[ TRIAL ACCOUNT ]${NC}"
    read -p "Duration (Min): " mins
    user="trial$(date +%s | tail -c 4)"
    pass=$user
    exp=$(($(date +%s) + mins * 60))
    echo "$user:$pass:$exp" >> $DB
    sync_config
    exp_date=$(date -d @$exp "+%d %b %Y %H:%M")
    DOMAIN=$(cat /etc/xray/domain 2>/dev/null || curl -s ipv4.icanhazip.com)
    
    clear
    echo -e ""
    echo -e "${YELLOW}CREATE AKUN TRIAL ZIVPN${NC}"
    echo -e "${YELLOW}┌────────────────────────┐${NC}"
    echo -e "${YELLOW}│${NC} Host   : ${DOMAIN}"
    echo -e "${YELLOW}│${NC} IP     : ${IP}"
    echo -e "${YELLOW}│${NC} ISP    : ${ISP}"
    echo -e "${YELLOW}│${NC} Pass   : ${pass}"
    echo -e "${YELLOW}│${NC} Expire : ${exp_date} ($mins Min)"
    echo -e "${YELLOW}└────────────────────────┘${NC}"
    echo -e "Terima kasih telah menggunakan layanan kami"
    
    TEXT="CREATE AKUN TRIAL ZIVPN
┌────────────────────────┐
│ Host   : <code>${DOMAIN}</code>
│ IP     : <code>${IP}</code>
│ ISP    : <code>${ISP}</code>
│ Pass   : <code>${pass}</code>
│ Expire : <code>${exp_date}</code>
└────────────────────────┘
Terima kasih telah menggunakan layanan kami"
    send_log "$TEXT"
    read -n 1 -s -r -p "Press [ Enter ] to back to menu"
}

# --- LIST AKUN MINIMALIS ---
function list_user() {
    clear
    echo -e "${CYAN}┌──────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│              LIST ACCOUNT ZIVPN              │${NC}"
    echo -e "${CYAN}├────┬─────────────────────┬───────────────────┤${NC}"
    echo -e "${CYAN}│ NO │      PASSWORD       │      EXPIRED      │${NC}"
    echo -e "${CYAN}├────┼─────────────────────┼───────────────────┤${NC}"
    
    i=1
    while IFS=: read -r u p e; do
        # Convert Expired Timestamp to Date
        exp_str=$(date -d @$e "+%d %b %Y")
        printf "${CYAN}│${NC} %-2s ${CYAN}│${NC} %-19s ${CYAN}│${NC} %-17s ${CYAN}│${NC}\n" "$i" "$p" "$exp_str"
        ((i++))
    done < $DB
    echo -e "${CYAN}└────┴─────────────────────┴───────────────────┘${NC}"
    echo -e "Total: $((i-1)) Users"
    read -n 1 -s -r -p "Press [ Enter ] to back to menu"
}

# --- RENEW AKUN (TABLE SELECTION) ---
function renew_user() {
    clear
    echo -e "${CYAN}┌──────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│               RENEW ACCOUNT                  │${NC}"
    echo -e "${CYAN}├────┬─────────────────────┬───────────────────┤${NC}"
    echo -e "${CYAN}│ NO │      PASSWORD       │      EXPIRED      │${NC}"
    echo -e "${CYAN}├────┼─────────────────────┼───────────────────┤${NC}"
    
    i=1
    while IFS=: read -r u p e; do
        exp_str=$(date -d @$e "+%d %b %Y")
        printf "${CYAN}│${NC} %-2s ${CYAN}│${NC} %-19s ${CYAN}│${NC} %-17s ${CYAN}│${NC}\n" "$i" "$p" "$exp_str"
        users[$i]=$u
        passes[$i]=$p
        exps[$i]=$e
        ((i++))
    done < $DB
    echo -e "${CYAN}└────┴─────────────────────┴───────────────────┘${NC}"
    
    read -p "Select Number : " num
    target=${users[$num]}
    pass_target=${passes[$num]}
    
    if [ -n "$target" ]; then
        read -p "Add Days : " days
        current_exp=${exps[$num]}
        now=$(date +%s)
        
        # Jika expired sudah lewat, mulai dari sekarang. Jika belum, tambah dari expired lama.
        if [[ "$current_exp" -gt "$now" ]]; then
            new_exp=$(($current_exp + $days * 86400))
        else
            new_exp=$(($now + $days * 86400))
        fi
        
        # Update Database
        grep -v "^$target:" $DB > $DB.tmp
        echo "$target:$pass_target:$new_exp" >> $DB.tmp
        mv $DB.tmp $DB
        sync_config
        
        new_date=$(date -d @$new_exp "+%d %b %Y")
        
        clear
        echo -e ""
        echo -e "${GREEN}┌────────────────────────┐${NC}"
        echo -e "${GREEN}│      SUCCESS RENEW     │${NC}"
        echo -e "${GREEN}│${NC} Pass   : ${pass_target}"
        echo -e "${GREEN}│${NC} Expire : ${new_date}"
        echo -e "${GREEN}└────────────────────────┘${NC}"
        
        TEXT="RENEW AKUN ZIVPN
┌────────────────────────┐
│ Pass   : <code>${pass_target}</code>
│ Expire : <code>${new_date}</code>
└────────────────────────┘"
        send_log "$TEXT"
    else
        echo -e "${RED}Invalid Number!${NC}"
    fi
    read -n 1 -s -r -p "Press [ Enter ] to back"
}

# --- DELETE AKUN (TABLE SELECTION) ---
function delete_user() {
    clear
    echo -e "${RED}┌──────────────────────────────────────────────┐${NC}"
    echo -e "${RED}│               DELETE ACCOUNT                 │${NC}"
    echo -e "${RED}├────┬─────────────────────┬───────────────────┤${NC}"
    echo -e "${RED}│ NO │      PASSWORD       │      EXPIRED      │${NC}"
    echo -e "${RED}├────┼─────────────────────┼───────────────────┤${NC}"
    
    i=1
    while IFS=: read -r u p e; do
        exp_str=$(date -d @$e "+%d %b %Y")
        printf "${RED}│${NC} %-2s ${RED}│${NC} %-19s ${RED}│${NC} %-17s ${RED}│${NC}\n" "$i" "$p" "$exp_str"
        users[$i]=$u
        passes[$i]=$p
        ((i++))
    done < $DB
    echo -e "${RED}└────┴─────────────────────┴───────────────────┘${NC}"
    
    read -p "Select Number : " num
    target=${users[$num]}
    pass_target=${passes[$num]}
    
    if [ -n "$target" ]; then
        grep -v "^$target:" $DB > $DB.tmp && mv $DB.tmp $DB
        sync_config
        
        clear
        echo -e ""
        echo -e "${RED}┌────────────────────────┐${NC}"
        echo -e "${RED}│     SUCCESS DELETE     │${NC}"
        echo -e "${RED}│${NC} Pass   : ${pass_target}"
        echo -e "${RED}│${NC} Status : Deleted"
        echo -e "${RED}└────────────────────────┘${NC}"
        
        TEXT="DELETE AKUN ZIVPN
┌────────────────────────┐
│ Pass   : <code>${pass_target}</code>
│ Status : Deleted
└────────────────────────┘"
        send_log "$TEXT"
    else
        echo -e "${RED}Invalid Number!${NC}"
    fi
    read -n 1 -s -r -p "Press [ Enter ] to back"
}

function change_domain() {
    read -p "New Domain: " d
    echo "$d" > /etc/xray/domain
    openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 -subj "/C=ID/CN=$d" -keyout $DIR/zivpn.key -out $DIR/zivpn.crt >/dev/null 2>&1
    systemctl restart $SERVICE; echo "Done."; read -p "Enter..."
}
function backup_menu() {
    echo "1) Backup Telegram"; echo "2) Restore URL"
    read -p "Opt: " c
    if [ "$c" == "1" ]; then /usr/local/bin/backup-tg; echo "Sent."; fi
    if [ "$c" == "2" ]; then read -p "URL: " u; wget -O backup.zip "$u" && unzip -o backup.zip -d / && systemctl restart $SERVICE; echo "Restored."; fi
    read -p "Enter..."
}
function setup_telegram() {
    read -p "Bot Token: " t; read -p "Chat ID: " c
    echo "TG_TOKEN='$t'" > $TG_CONFIG; echo "TG_ID='$c'" >> $TG_CONFIG
    echo "Saved."; read -p "Enter..."
}

while true; do show_menu; done
END_OF_MENU
chmod +x $MENU_BIN

# ==========================================
# 5. BACKUP & LANDING PAGE
# ==========================================
echo -e "${CYAN}[4/5] Finalizing...${NC}"

cat << 'EOF' > $BACKUP_BIN
#!/bin/bash
TG_CONFIG="/etc/zivpn/tg_backup.conf"
if [ ! -f "$TG_CONFIG" ]; then exit 0; fi
source $TG_CONFIG
DATE=$(date +%Y-%m-%d); IP=$(curl -s ipv4.icanhazip.com)
FILENAME="backup-$IP-$DATE.zip"
cd /root; zip -r $FILENAME /etc/zivpn/user.db /etc/zivpn/config.json /etc/zivpn/apikey /etc/zivpn/zivpn.crt /etc/zivpn/zivpn.key >/dev/null 2>&1
curl -F chat_id="$TG_ID" -F document=@"$FILENAME" -F caption="✅ Backup $IP $DATE" "https://api.telegram.org/bot$TG_TOKEN/sendDocument" >/dev/null 2>&1
rm $FILENAME
EOF
chmod +x $BACKUP_BIN

# Auto Backup 00:00
crontab -l | grep -v "backup-tg" | crontab -
(crontab -l 2>/dev/null; echo "0 0 * * * /usr/local/bin/backup-tg") | crontab -
service cron restart

cat << 'EOF' > $LANDING_BIN
#!/bin/bash
CYAN='\033[0;36m'; NC='\033[0m'
clear
echo -e "${CYAN}┌──────────────────────────────────────────────────┐${NC}"
echo -e "${CYAN}│${NC}             WINTUNELING ZIVPN SERVER           ${CYAN}│${NC}"
echo -e "${CYAN}└──────────────────────────────────────────────────┘${NC}"
echo -e ""
echo -e "${CYAN}       >>> PRESS [ ENTER ] TO ENTER MENU <<<${NC}"
read -n 1 -s -r -p ""
menu
EOF
chmod +x $LANDING_BIN

# Set Landing Page in Profile
if ! grep -q "landing-page" /root/.profile; then
cat >> /root/.profile << 'EOF'
if [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ]; then
    if [ -f "/usr/bin/landing-page" ]; then /usr/bin/landing-page; fi
fi
EOF
fi

systemctl daemon-reload
systemctl enable $SERVICE_VPN $SERVICE_API
systemctl start $SERVICE_VPN $SERVICE_API

clear
echo -e "${GREEN}┌──────────────────────────────────────────────────┐${NC}"
echo -e "${YELLOW}             SUCCESFULLY INSTALL SCRIPT            ${NC}"
echo -e "${GREEN}└──────────────────────────────────────────────────┘${NC}"
echo -e " Wait for 5s server will automatically rebooting"
echo -e " Rebooting in 5s..."
sleep 5
reboot