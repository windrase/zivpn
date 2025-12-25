#!/bin/bash
# ============================================================
# WINTUNELING VPN - CLIENT INSTALLER (FINAL VERSION)
# ============================================================

# ⚠️ GANTI IP DI BAWAH INI DENGAN IP VPS ADMIN (TEMPAT BOT BERJALAN) ⚠️
# JANGAN GUNAKAN GITHUB JIKA PAKAI BOT ADMIN
LICENSE_URL="http://129.226.206.227:3000/whitelist"

# --- Konfigurasi Variable ---
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

# --- Warna ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# 1. CEK LICENSE & INFO CLIENT
clear
echo -e "${YELLOW}[INFO] Checking License Wintunneling...${NC}"
MYIP=$(curl -s ipv4.icanhazip.com)
LICENSE_DATA=$(curl -s --connect-timeout 5 "$LICENSE_URL")

if echo "$LICENSE_DATA" | grep -q "$MYIP"; then
    CLIENT_DATA=$(echo "$LICENSE_DATA" | grep "$MYIP")
    CLIENT_NAME=$(echo "$CLIENT_DATA" | cut -d: -f2)
    EXP_DATE=$(echo "$CLIENT_DATA" | cut -d: -f3)
    TODAY=$(date +%Y-%m-%d)
    
    if [[ "$TODAY" > "$EXP_DATE" ]]; then
        echo -e "${RED}❌ LICENSE EXPIRED ($EXP_DATE) ❌${NC}"
        echo -e "Silakan hubungi Admin t.me/WINTUNELINGVPNN untuk perpanjang."
        exit 1
    else
        echo -e "${GREEN}✅ License Valid! Welcome $CLIENT_NAME${NC}"
        mkdir -p /etc/wintunnel
        echo "$CLIENT_NAME" > /etc/wintunnel/client
        echo "$EXP_DATE" > /etc/wintunnel/exp
        sleep 2
    fi
else
    echo -e "${RED}❌ AKSES DITOLAK! IP ($MYIP) TIDAK TERDAFTAR ❌${NC}"
    echo -e "Hubungi Admin untuk Register IP."
    exit 1
fi

# 2. SYSTEM PREP
clear
echo -e "${CYAN}[1/7] Preparing System...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y >/dev/null 2>&1
apt-get install -y curl wget jq openssl zip unzip cron net-tools lsb-release gnupg vnstat bc >/dev/null 2>&1

# Setup Vnstat
systemctl enable vnstat
systemctl start vnstat

# Install Node.js
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash - >/dev/null 2>&1
    apt-get install -y nodejs >/dev/null 2>&1
fi

# 3. INSTALL ZIVPN CORE
echo -e "${CYAN}[2/7] Installing Core...${NC}"
systemctl stop $SERVICE_VPN >/dev/null 2>&1
mkdir -p $DIR

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
    -subj "/C=ID/ST=VPN/L=VPN/O=WINTUNNELING/CN=$MYIP" \
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
INTF=$(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1)
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
# WINTUNELING AUTO BACKUP SCRIPT
TG_CONFIG="/etc/zivpn/tg_backup.conf"
if [ ! -f "$TG_CONFIG" ]; then exit 0; fi
source $TG_CONFIG

DATE=$(date +%Y-%m-%d)
TIME=$(date +%H:%M:%S)
ISP=$(curl -s ip-api.com/json | jq -r .isp)
CITY=$(curl -s ip-api.com/json | jq -r .city)
IP=$(curl -s ipv4.icanhazip.com)
FILENAME="backup-$IP-$DATE.zip"

# Zip Data Penting
zip -r /root/$FILENAME /etc/zivpn/user.db /etc/zivpn/config.json /etc/zivpn/apikey /etc/zivpn/zivpn.crt /etc/zivpn/zivpn.key > /dev/null 2>&1

CAPTION="🤖 *AUTO BACKUP FILE*
━━━━━━━━━━━━━━━━━━━━
📅 Date  : \`$DATE\`
⏰ Time  : \`$TIME\`
🌐 IP    : \`$IP\`
🏢 ISP   : \`$ISP\`
🏙️ City  : \`$CITY\`
━━━━━━━━━━━━━━━━━━━━"

# Kirim ke Telegram
curl -s -F chat_id="$TG_ID" -F document=@"/root/$FILENAME" -F caption="$CAPTION" -F parse_mode="Markdown" "https://api.telegram.org/bot$TG_TOKEN/sendDocument" > /dev/null

rm /root/$FILENAME
EOF
chmod +x $BACKUP_BIN

# 7. MENU PREMIUM (DASHBOARD STYLE)
echo -e "${CYAN}[6/7] Installing Script Menu...${NC}"

cat << 'EOF' > $MENU_BIN
#!/bin/bash
# WINTUNELING VPN MENU - DASHBOARD STYLE

DIR="/etc/zivpn"
DB="$DIR/user.db"
CONFIG="$DIR/config.json"
API_KEY_FILE="$DIR/apikey"
TG_CONFIG="$DIR/tg_backup.conf"
SERVICE="zivpn"

# Colors
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

function draw_bar() {
    local perc=$1
    local size=10
    local filled=$(printf "%.0f" $(echo "$perc * $size / 100" | bc))
    local empty=$((size - filled))
    printf "${PURPLE}"
    for ((i=0; i<filled; i++)); do printf "█"; done
    printf "${GRAY}"
    for ((i=0; i<empty; i++)); do printf "░"; done
    printf "${NC}"
}

function get_info() {
    OS=$(lsb_release -d | cut -f2 | tr -d '"' | sed 's/Ubuntu //')
    ISP=$(curl -s ip-api.com/json | jq -r .isp)
    CITY=$(curl -s ip-api.com/json | jq -r .city)
    IP=$(curl -s ipv4.icanhazip.com)
    CLIENT=$(cat /etc/wintunnel/client 2>/dev/null || echo "Unknown")
    EXP_SCRIPT=$(cat /etc/wintunnel/exp 2>/dev/null || echo "Unknown")
    DOMAIN=$(openssl x509 -noout -subject -in $DIR/zivpn.crt | sed -n 's/^.*CN = //p')
    [ -z "$DOMAIN" ] && DOMAIN="$IP"
    TOTAL_USER=$(wc -l < $DB 2>/dev/null || echo 0)
    
    # RAM
    total_ram=$(free -m | awk 'NR==2{print $2}')
    used_ram=$(free -m | awk 'NR==2{print $3}')
    ram_perc=$(awk "BEGIN {printf \"%.0f\", $used_ram/$total_ram*100}")
    
    if systemctl is-active --quiet $SERVICE; then
        STATUS="${GREEN}ACTIVE${NC}"
    else
        STATUS="${RED}DOWN${NC}"
    fi
    
    TX_TODAY=$(vnstat -d --oneline | awk -F';' '{print $6}' || echo "N/A")
    TX_MONTH=$(vnstat -m --oneline | awk -F';' '{print $11}' || echo "N/A")
    
    # API Status
    API_KEY=$(cat $API_KEY_FILE)
    if [ -n "$API_KEY" ]; then API_STAT="${GREEN}ON${NC}"; else API_STAT="${RED}OFF${NC}"; fi
}

function show_menu() {
    clear
    get_info
    echo -e "${CYAN} ╭────────────────────────────────────────────────────────╮${NC}"
    echo -e "${CYAN} │${WHITE}${BOLD}               WINTUNELING VPN                ${NC}${CYAN}│${NC}"
    echo -e "${CYAN} ╰────────────────────────────────────────────────────────╯${NC}"
    echo -e "${CYAN} ┌─────────────── ───[ SYSTEM INFO ]──────────────────────┐${NC}"
    echo -e "${CYAN} │${NC} ${GRAY}OS      :${NC} $OS"
    echo -e "${CYAN} │${NC} ${GRAY}IP      :${NC} $IP"
    echo -e "${CYAN} │${NC} ${GRAY}ISP     :${NC} $ISP ($CITY)"
    echo -e "${CYAN} │${NC} ${GRAY}RAM     :${NC} $(draw_bar $ram_perc) $ram_perc% ($used_ram MB)"
    echo -e "${CYAN} └────────────────────────────────────────────────────────┘${NC}"
    echo -e "${CYAN} ┌─────────────────────[ LICENSE ] ───────────────────────┐${NC}"
    echo -e "${CYAN} │${NC} ${GRAY}Client  :${NC} ${YELLOW}$CLIENT${NC}"
    echo -e "${CYAN} │${NC} ${GRAY}Expired :${NC} $EXP_SCRIPT"
    echo -e "${CYAN} └────────────────────────────────────────────────────────┘${NC}"
    echo -e "${CYAN} ┌────────────────── [ VPN STATUS ]───────────────────────┐${NC}"
    echo -e "${CYAN} │${NC} ${GRAY}Domain  :${NC} ${GREEN}$DOMAIN${NC}"
    echo -e "${CYAN} │${NC} ${GRAY}Status  :${NC} $STATUS        ${GRAY}Users :${NC} ${WHITE}$TOTAL_USER${NC}"
    echo -e "${CYAN} │${NC} ${GRAY}API Key :${NC} $API_STAT"
    echo -e "${CYAN} └────────────────────────────────────────────────────────┘${NC}"
    echo -e ""
    echo -e " ${CYAN}[ MENU MANAGEMENT ]${NC}"
    echo -e " ${WHITE}[1]${NC} Create Account      ${WHITE}[2]${NC} Create Trial"
    echo -e " ${WHITE}[3]${NC} Renew Account       ${WHITE}[4]${NC} Delete Account"
    echo -e " ${WHITE}[5]${NC} List Users          ${WHITE}[6]${NC} Change Domain"
    echo -e ""
    echo -e " ${CYAN}[ SYSTEM & BACKUP ]${NC}"
    echo -e " ${WHITE}[7]${NC} Check API Key       ${WHITE}[8]${NC} Restart Service"
    echo -e " ${WHITE}[9]${NC} Backup Now          ${WHITE}[10]${NC} Restore Data"
    echo -e " ${WHITE}[11]${NC} Auto Backup         ${WHITE}[12]${NC} Notif Telegram"
    echo -e ""
    echo -e "                         ${RED}[0] Exit${NC}"
    echo -e "${CYAN} ──────────────────────────────────────────────────────────${NC}"
    read -p " Select Option: " opt
    case $opt in
        1) create_user ;;
        2) trial_user ;;
        3) renew_user ;;
        4) delete_user ;;
        5) list_user ;;
        6) change_domain ;;
        7) show_api ;;
        8) systemctl restart $SERVICE; echo -e "${GREEN}Service Restarted.${NC}"; sleep 1 ;;
        9) backup_data ;;
        10) restore_data ;;
        11) auto_backup_setup ;;
        12) reset_tg_config ;;
        0) exit 0 ;;
    esac
}

function backup_data() {
    clear
    echo -e "${CYAN}[ BACKUP DATA TO TELEGRAM ]${NC}"
    if [ ! -f "$TG_CONFIG" ]; then
        echo -e "${YELLOW}Telegram Config Not Found!${NC}"
        read -p "Enter Bot Token : " token
        read -p "Enter Chat ID   : " chatid
        echo "TG_TOKEN='$token'" > $TG_CONFIG
        echo "TG_ID='$chatid'" >> $TG_CONFIG
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
        echo -e "${RED}Please Setup 'Backup Now' [Menu 9] first!${NC}"
        read -p "Enter..."
        return
    fi
    read -p "Set Jam (Format HH:MM, contoh 00:00) : " jam
    if [[ ! $jam =~ ^([0-1][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
        echo -e "${RED}Format Salah!${NC}"; read -p "Enter..."; return
    fi
    hh=$(echo $jam | cut -d: -f1)
    mm=$(echo $jam | cut -d: -f2)
    cat << EOF > /etc/cron.d/zivpn_autobackup
# Auto Backup Wintunneling
$mm $hh * * * root /usr/local/bin/backup-tg
EOF
    service cron restart
    echo -e "${GREEN}✅ Auto Backup Diatur pada jam $jam${NC}"
    read -p "Press Enter..."
}

function reset_tg_config() {
    clear
    echo -e "${CYAN}[ RESET TELEGRAM CONFIG ]${NC}"
    if [ -f "$TG_CONFIG" ]; then
        rm "$TG_CONFIG"
        echo -e "${GREEN}✅ Konfigurasi Telegram berhasil direset!${NC}"
    else
        echo -e "${RED}⚠️ Belum ada konfigurasi.${NC}"
    fi
    read -p "Press Enter..."
}

function restore_data() {
    clear
    echo -e "${CYAN}[ RESTORE DATA ]${NC}"
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
    read -p "Press Enter..."
}

function create_user() {
    echo -e "\n${CYAN}┌── [ CREATE ACCOUNT ]${NC}"
    read -p "│ Username : " user
    if grep -q "^$user:" $DB; then echo -e "│ ${RED}User Exists!${NC}"; read -p "└ Enter..."; return; fi
    read -p "│ Password : " pass
    read -p "│ Days     : " days
    exp=$(($(date +%s) + days * 86400))
    echo "$user:$pass:$exp" >> $DB
    sync_config
    echo -e "│\n│ ${GREEN}SUCCESS! Account Created.${NC}"
    echo -e "│ Domain : $DOMAIN\n│ User   : $user\n│ Pass   : $pass\n│ Exp    : $(date -d @$exp "+%d %b %Y")"
    echo -e "${CYAN}└─────────────────────────${NC}"
    read -p "Press Enter..."
}

function trial_user() {
    echo -e "\n${CYAN}┌── [ TRIAL ACCOUNT ]${NC}"
    read -p "│ Minutes : " mins
    user="trial$(date +%s | tail -c 3)"
    pass=$user
    exp=$(($(date +%s) + mins * 60))
    echo "$user:$pass:$exp" >> $DB
    sync_config
    echo -e "│\n│ ${GREEN}SUCCESS! Trial Created.${NC}"
    echo -e "│ Domain : $DOMAIN\n│ User   : $user\n│ Pass   : $pass\n│ Exp    : $mins Minutes"
    echo -e "${CYAN}└─────────────────────────${NC}"
    read -p "Press Enter..."
}

function renew_user() {
    echo -e "\n${CYAN}[ RENEW ]${NC}"
    read -p "Username : " user
    if ! grep -q "^$user:" $DB; then echo "Not found"; read -p "Enter..."; return; fi
    read -p "Add Days : " days
    TMP=$(mktemp)
    while IFS=: read -r u p e; do
        if [ "$u" == "$user" ]; then
            now=$(date +%s); [ $e -lt $now ] && new_exp=$now || new_exp=$e
            final_exp=$((new_exp + days * 86400))
            echo "$u:$p:$final_exp" >> $TMP
        else echo "$u:$p:$e" >> $TMP; fi
    done < $DB
    mv $TMP $DB; sync_config; read -p "Enter..."
}

function delete_user() {
    echo -e "\n${CYAN}[ DELETE ]${NC}"
    read -p "Username : " user
    grep -v "^$user:" $DB > $DB.tmp && mv $DB.tmp $DB
    sync_config; echo -e "${GREEN}Deleted.${NC}"; read -p "Enter..."
}

function list_user() {
    clear; echo -e "${CYAN}USER LIST${NC}"; echo "---------"
    while IFS=: read -r u p e; do
        echo -e "$u | Exp: $(date -d @$e "+%F")"
    done < $DB
    echo "---------"; read -p "Enter..."
}

function change_domain() {
    echo -e "\n${CYAN}[ CHANGE DOMAIN ]${NC}"
    read -p "New Domain: " d
    openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 -subj "/C=ID/CN=$d" -keyout $DIR/zivpn.key -out $DIR/zivpn.crt >/dev/null 2>&1
    systemctl restart $SERVICE; echo -e "${GREEN}Updated to $d${NC}"; read -p "Enter..."
}

function show_api() {
    clear
    echo -e "${CYAN}┌── [ API CONFIG ]${NC}"
    echo -e "│ Key  : ${YELLOW}$(cat $API_KEY_FILE)${NC}"
    echo -e "│ Port : ${YELLOW}5888${NC}"
    echo -e "${CYAN}└─────────────────${NC}"
    read -p "Enter..."
}

function sync_config() {
    PASS_LIST=$(awk -F: '{printf "\"%s\",", $2}' $DB | sed 's/,$//')
    [ -z "$PASS_LIST" ] && PASS_LIST="\"default\""
    jq ".auth.config = [$PASS_LIST]" $CONFIG > $CONFIG.tmp && mv $CONFIG.tmp $CONFIG
    systemctl restart $SERVICE
}

while true; do show_menu; done
EOF
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
