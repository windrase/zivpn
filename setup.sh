#!/bin/bash
# WINTUNELING VPN - FINAL ULTIMATE V16 (Fix Backup Domain & Smart Restore)
# Features: Real Newline Fix, Perfect Box, Smart Restore (Keep Bot Token)

# ==================================================
#  ⚠️ KONFIGURASI GITHUB (WAJIB DIISI) ⚠️
# ==================================================
REPO_URL="https://raw.githubusercontent.com/windrase/zivpn/refs/heads/main/setup.sh"
# ==================================================

# ==========================================
# 0. UPDATE MODE CHECKER
# ==========================================
if [ "$1" == "--update" ]; then
    echo -e "\n\033[0;33m[INFO] Starting Update Process...\033[0m"
    UPDATE_MODE="true"
else
    UPDATE_MODE="false"
fi

# ==========================================
# 1. PROFILE & PERMISSIONS
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
# 2. CONFIGURATION PATHS
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
CYAN='\033[0;36m'; GREEN='\033[0;32m'; RED='\033[0;31m'
YELLOW='\033[0;33m'; PURPLE='\033[0;35m'; BLUE='\033[0;34m'
WHITE='\033[1;37m'; NC='\033[0m'

# ==========================================
# 3. CORE FILE GENERATOR (API & MENU)
# ==========================================
function generate_core_files() {
    echo -e "${CYAN}[+] Updating Core Files...${NC}"
    mkdir -p $DIR $DIR_API

    # --- 1. GENERATE API SERVER ---
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
            fs.writeFileSync('/tmp/tg_msg.txt', message);
            const cmd = `/usr/bin/curl -s -X POST "https://api.telegram.org/bot${token}/sendMessage" -d chat_id="${id}" -d parse_mode="HTML" --data-urlencode text@/tmp/tg_msg.txt > /dev/null 2>&1`;
            shell.exec(cmd, {async:true});
        }
    } catch (e) {}
}

function getWIB(ms) {
    const d = new Date(ms);
    return d.toLocaleDateString('en-GB', {
        timeZone: 'Asia/Jakarta',
        day: 'numeric', month: 'short', year: 'numeric',
        hour: '2-digit', minute: '2-digit', hour12: false
    }).replace(',', '') + " WIB";
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

    const dateStr = getWIB(expDateMs);
const msg = `<b>CREATE AKUN ZIVPN</b>
<pre>┌──────────────────────────┐
│ Host   : ${SERVER_DOMAIN}
│ IP     : ${SERVER_IP}
│ ISP    : ${SERVER_ISP}
│ Pass   : ${password}
│ Expire : ${dateStr}
└──────────────────────────┘</pre>
Terima kasih telah menggunakan layanan kami`;

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
    
    const dateStr = getWIB(expDateMs);
const msg = `<b>CREATE AKUN TRIAL ZIVPN</b>
<pre>┌──────────────────────────┐
│ Host   : ${SERVER_DOMAIN}
│ IP     : ${SERVER_IP}
│ ISP    : ${SERVER_ISP}
│ Pass   : ${user}
│ Expire : ${dateStr}
└──────────────────────────┘</pre>
Terima kasih telah menggunakan layanan kami`;

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
    
const msg = `<b>RENEW AKUN ZIVPN</b>
┌──────────────────────────┐
│ Pass   : ${password}
│ Added  : ${expDays} Days
└──────────────────────────┘`;
    sendLog(msg);
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
    res.json({ status: 'success', message: 'Deleted' });
});

app.listen(port, () => console.log(`API running on ${port}`));
EOF

    # --- 2. UPDATE SYSTEMD SERVICE ---
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

    # --- 3. GENERATE MENU SCRIPT (SMART RESTORE INCLUDED) ---
cat << 'END_OF_MENU' > $MENU_BIN
#!/bin/bash
DIR="/etc/zivpn"
DB="$DIR/user.db"
CONFIG="$DIR/config.json"
API_KEY_FILE="$DIR/apikey"
TG_CONFIG="$DIR/tg_backup.conf"
SERVICE="zivpn"
SERVICE_API="zivpn-api"
REPO_URL="REPLACE_THIS_WITH_YOUR_REPO_URL" # Placeholder

NC='\033[0m'; PURPLE='\033[0;35m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; WHITE='\033[1;37m'; GREEN='\033[0;32m'; RED='\033[0;31m'; BLUE='\033[0;34m'

function send_log() {
    if [ ! -f "$TG_CONFIG" ]; then return; fi
    source "$TG_CONFIG"
    # Write to temp file for safe transmission
    echo "$1" > /tmp/tg_msg.txt
    curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
        -d chat_id="${TG_ID}" -d parse_mode="HTML" --data-urlencode text@/tmp/tg_msg.txt > /dev/null 2>&1
}

function get_info() {
    OS=$(lsb_release -d | cut -f2 | tr -d '"' | sed 's/Ubuntu //')
    IP=$(curl -s ipv4.icanhazip.com)
    DOMAIN=$(openssl x509 -noout -subject -in $DIR/zivpn.crt 2>/dev/null | sed -n 's/^.*CN = //p')
    [ -z "$DOMAIN" ] && DOMAIN="No Domain"
    JSON_IP=$(curl -s ip-api.com/json)
    ISP=$(echo "$JSON_IP" | jq -r .isp)
    CLIENT=$(cat /etc/wintunnel/client 2>/dev/null || echo "User")
    EXP_DATE=$(cat /etc/wintunnel/exp 2>/dev/null || echo "Lifetime")
    RAM_USED=$(free -m | awk 'NR==2{print $3}')
    RAM_TOTAL=$(free -m | awk 'NR==2{print $2}')
    RAM_PERC=$(awk "BEGIN {printf \"%.0f\", $RAM_USED/$RAM_TOTAL*100}")
    CPU_MODEL=$(lscpu | grep "Model name" | cut -d: -f2 | sed 's/^ //;s/  */ /g' | cut -c1-20)
    CPU_CORES=$(nproc)
    UPTIME=$(uptime -p | sed 's/up //')
    USERS=$(wc -l < $DB 2>/dev/null || echo "0")
    API_KEY=$(cat $API_KEY_FILE 2>/dev/null)
    INTF=$(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1)
    BW_DAILY=$(vnstat -i $INTF -d --oneline | awk -F\; '{print $6}')
    [ -z "$BW_DAILY" ] && BW_DAILY="0 B"
    BW_MONTHLY=$(vnstat -i $INTF -m --oneline | awk -F\; '{print $6}')
    [ -z "$BW_MONTHLY" ] && BW_MONTHLY="0 B"
    if systemctl is-active --quiet $SERVICE; then STAT_VPN="${GREEN}ON${NC}"; else STAT_VPN="${RED}OFF${NC}"; fi
    if systemctl is-active --quiet $SERVICE_API; then STAT_API="${GREEN}ON${NC}"; else STAT_API="${RED}OFF${NC}"; fi
}

function show_menu() {
    clear
    get_info
    echo -e "${PURPLE} ╭────────────────────────────────────────────────${NC}"
    echo -e "${PURPLE} │${CYAN}                WINTUNELING ZIVPN${NC}"
    echo -e "${PURPLE} ├────────────────────────────────────────────────${NC}"
    echo -e "${PURPLE} │${CYAN} OS      : ${WHITE}$OS${NC}"
    echo -e "${PURPLE} │${CYAN} IP      : ${WHITE}$IP${NC}"
    echo -e "${PURPLE} │${CYAN} Domain  : ${WHITE}$DOMAIN${NC}"
    echo -e "${PURPLE} │${CYAN} ISP     : ${WHITE}$ISP${NC}"
    echo -e "${PURPLE} ├─────────────────────────────────────────────────${NC}"
    echo -e "${PURPLE} │${CYAN} Client  : ${WHITE}$CLIENT${NC}"
    echo -e "${PURPLE} │${CYAN} Exp     : ${WHITE}$EXP_DATE${NC}"
    echo -e "${PURPLE} ├─────────────────────────────────────────────────${NC}"
    echo -e "${PURPLE} │${CYAN} RAM     : ${WHITE}$RAM_USED/$RAM_TOTAL MB ($RAM_PERC%)${NC}"
    echo -e "${PURPLE} │${CYAN} CPU     :${WHITE}$CPU_MODEL ($CPU_CORES Core)${NC}"
    echo -e "${PURPLE} │${CYAN} Uptime  : ${WHITE}$UPTIME${NC}"
    echo -e "${PURPLE} │${CYAN} Users   : ${WHITE}$USERS Accounts${NC}"
    echo -e "${PURPLE} ├─────────────────────────────────────────────────${NC}"
    echo -e "${PURPLE} │${CYAN} Today   : ${WHITE}$BW_DAILY${NC}"
    echo -e "${PURPLE} │${CYAN} Month   : ${WHITE}$BW_MONTHLY${NC}"
    echo -e "${PURPLE} ├─────────────────────────────────────────────────${NC}"
    echo -e "${PURPLE} │${CYAN} Service : ${STAT_VPN}    ${CYAN}API : ${STAT_API}${NC}   ${CYAN} API Key : ${YELLOW}$API_KEY${NC}"
    echo -e "${PURPLE} ╰─────────────────────────────────────────────────${NC}"
    echo -e ""
    echo -e "  ${BLUE}[1]${NC} Create Account        ${BLUE}[2]${NC} Create Trial"
    echo -e "  ${BLUE}[3]${NC} Renew Account         ${BLUE}[4]${NC} Delete Account"
    echo -e "  ${BLUE}[5]${NC} List Accounts         ${BLUE}[6]${NC} Change Domain"
    echo -e "  ${BLUE}[7]${NC} Backup/Restore        ${BLUE}[8]${NC} Setup Notif"
    echo -e "  ${BLUE}[9]${NC} Restart Service       ${BLUE}[10]${NC} Generate API"
    echo -e "  ${BLUE}[11]${NC} Cek Sertifikat       ${BLUE}[12]${NC} Set Auto Backup"
    echo -e "  ${BLUE}[13]${NC} Update Script        ${BLUE}[0]${NC} Exit"
    echo -e ""
    echo -ne "  ${YELLOW}Select Option : ${NC}"
    read opt
    case $opt in
        1) create_user ;; 2) trial_user ;; 3) renew_user ;; 4) delete_user ;;
        5) list_user ;; 6) change_domain ;; 7) backup_menu ;; 8) setup_telegram ;;
        9) systemctl restart $SERVICE; echo "Restarted."; sleep 1 ;; 
        10) generate_api ;; 11) clear; cat /etc/zivpn/zivpn.crt; echo ""; read -p "Enter..." ;;
        12) set_backup_timer ;; 
        13) update_script ;;
        0) exit 0 ;; *) echo "Invalid"; sleep 1 ;;
    esac
}

function update_script() {
    echo -e "\n${CYAN}[ UPDATE SCRIPT ]${NC}"
    if [ -f "$TG_CONFIG" ]; then
        echo -e "${YELLOW}Creating Backup before update...${NC}"
        /usr/local/bin/backup-tg
        echo -e "${GREEN}Backup Sent to Telegram!${NC}"
    fi
    echo -e "${YELLOW}Downloading latest update...${NC}"
    wget -qO /root/setup.sh "REPLACE_THIS_WITH_YOUR_REPO_URL"
    if [ $? -eq 0 ]; then
        chmod +x /root/setup.sh
        /root/setup.sh --update
    else
        echo -e "${RED}Failed to download update script! Check Internet.${NC}"
        sleep 2
    fi
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
    echo -e "\n${CYAN}CREATE AKUN ZIVPN${NC}\n${CYAN}┌──────────────────────────┐${NC}\n${CYAN}│${NC} Host   : ${DOMAIN}\n${CYAN}│${NC} IP     : ${IP}\n${CYAN}│${NC} ISP    : ${ISP}\n${CYAN}│${NC} Pass   : ${pass}\n${CYAN}│${NC} Expire : ${exp_date}\n${CYAN}└──────────────────────────┘${NC}\nTerima kasih telah menggunakan layanan kami"
    # BOX TELEGRAM
TEXT="<b>CREATE AKUN ZIVPN</b>
┌──────────────────────────┐
│ Host   : ${DOMAIN}
│ IP     : ${IP}
│ ISP    : ${ISP}
│ Pass   : ${pass}
│ Expire : ${exp_date}
└──────────────────────────┘
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
    echo -e "\n${YELLOW}CREATE AKUN TRIAL ZIVPN${NC}\n${YELLOW}┌──────────────────────────┐${NC}\n${YELLOW}│${NC} Host   : ${DOMAIN}\n${YELLOW}│${NC} IP     : ${IP}\n${YELLOW}│${NC} ISP    : ${ISP}\n${YELLOW}│${NC} Pass   : ${pass}\n${YELLOW}│${NC} Expire : ${exp_date} ($mins Min)\n${YELLOW}└──────────────────────────┘${NC}\nTerima kasih telah menggunakan layanan kami"
    # BOX TELEGRAM
TEXT="<b>CREATE AKUN TRIAL ZIVPN</b>
┌──────────────────────────┐
│ Host   : ${DOMAIN}
│ IP     : ${IP}
│ ISP    : ${ISP}
│ Pass   : ${pass}
│ Expire : ${exp_date}
└──────────────────────────┘
Terima kasih telah menggunakan layanan kami"
    send_log "$TEXT"
    read -n 1 -s -r -p "Press [ Enter ] to back to menu"
}

function list_user() {
    clear
    echo -e "${CYAN}┌──────────────────────────────────────────────┐${NC}\n${CYAN}│               LIST ACCOUNT ZIVPN             │${NC}\n${CYAN}├────┬─────────────────────┬───────────────────┤${NC}\n${CYAN}│ NO │      PASSWORD       │      EXPIRED      │${NC}\n${CYAN}├────┼─────────────────────┼───────────────────┤${NC}"
    i=1
    while IFS=: read -r u p e; do
        exp_str=$(date -d @$e "+%d %b %Y")
        printf "${CYAN}│${NC} %-2s ${CYAN}│${NC} %-19s ${CYAN}│${NC} %-17s ${CYAN}│${NC}\n" "$i" "$p" "$exp_str"
        ((i++))
    done < $DB
    echo -e "${CYAN}└────┴─────────────────────┴───────────────────┘${NC}"
    echo -e "Total: $((i-1)) Users"
    read -n 1 -s -r -p "Press [ Enter ] to back to menu"
}

function renew_user() {
    clear
    echo -e "${CYAN}┌──────────────────────────────────────────────┐${NC}\n${CYAN}│               RENEW ACCOUNT                  │${NC}\n${CYAN}├────┬─────────────────────┬───────────────────┤${NC}\n${CYAN}│ NO │      PASSWORD       │      EXPIRED      │${NC}\n${CYAN}├────┼─────────────────────┼───────────────────┤${NC}"
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
        if [[ "$current_exp" -gt "$now" ]]; then new_exp=$(($current_exp + $days * 86400)); else new_exp=$(($now + $days * 86400)); fi
        grep -v "^$target:" $DB > $DB.tmp
        echo "$target:$pass_target:$new_exp" >> $DB.tmp
        mv $DB.tmp $DB
        sync_config
        new_date=$(date -d @$new_exp "+%d %b %Y")
        clear
        echo -e "\n${GREEN}┌────────────────────────┐${NC}\n${GREEN}│      SUCCESS RENEW     │${NC}\n${GREEN}│${NC} Pass   : ${pass_target}\n${GREEN}│${NC} Expire : ${new_date}\n${GREEN}└────────────────────────┘${NC}"
TEXT="<b>RENEW AKUN ZIVPN</b>
┌──────────────────────────┐
│ Pass   : ${pass_target}
│ Expire : ${new_date}
└──────────────────────────┘"
        send_log "$TEXT"
    else echo -e "${RED}Invalid Number!${NC}"; fi
    read -n 1 -s -r -p "Press [ Enter ] to back"
}

function delete_user() {
    clear
    echo -e "${RED}┌──────────────────────────────────────────────┐${NC}\n${RED}│               DELETE ACCOUNT                 │${NC}\n${RED}├────┬─────────────────────┬───────────────────┤${NC}\n${RED}│ NO │      PASSWORD       │      EXPIRED      │${NC}\n${RED}├────┼─────────────────────┼───────────────────┤${NC}"
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
    if [ -n "$target" ]; then
        grep -v "^$target:" $DB > $DB.tmp && mv $DB.tmp $DB
        sync_config
        clear; echo -e "${RED}Deleted Successfully!${NC}"
    else echo -e "${RED}Invalid Number!${NC}"; fi
    read -n 1 -s -r -p "Press [ Enter ] to back"
}

function change_domain() {
    read -p "New Domain: " d
    echo "$d" > /etc/xray/domain
    rm -rf /etc/zivpn/zivpn.key /etc/zivpn/zivpn.crt
    openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 -subj "/C=ID/CN=$d" -keyout $DIR/zivpn.key -out $DIR/zivpn.crt >/dev/null 2>&1
    systemctl restart $SERVICE; echo "Done."; read -p "Enter..."
}

function backup_menu() {
    clear
    TG_CONFIG="/etc/zivpn/tg_backup.conf"
    echo -e "${CYAN}┌──────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│               BACKUP & RESTORE               │${NC}"
    echo -e "${CYAN}└──────────────────────────────────────────────┘${NC}"
    echo -e " [1] Backup Data (To Telegram)"
    echo -e " [2] Restore Data (From URL)"
    echo -e " [0] Exit"
    echo -e ""
    read -p " Select: " opt
    if [ "$opt" == "1" ]; then
        if [ ! -f "$TG_CONFIG" ]; then
            echo -e "\n${RED}⚠️  Error: Telegram Not Configured!${NC}"
            echo -e "Please select menu [8] Setup Notif first."
            read -n 1 -s -r -p "Press Enter to continue..."
            return
        fi
        echo -e "\n${YELLOW}Sending Backup...${NC}"
        /usr/local/bin/backup-tg
        read -n 1 -s -r -p "Press Enter to continue..."
    elif [ "$opt" == "2" ]; then
        echo -e "\n${YELLOW}[ RESTORE DATA FROM TELEGRAM ]${NC}"
        echo -e "1. Forward file Backup dari Channel ke Bot Direct Link."
        echo -e "2. Copy Direct Link yang diberikan bot."
        echo -e "3. Paste link tersebut di bawah ini.\n"
        read -p "Input Direct Link: " url
        if [ -n "$url" ]; then
            
            # --- SMART RESTORE: AMANKAN BOT CONFIG SAAT INI ---
            echo -e "${YELLOW}Checking current Telegram config...${NC}"
            KEEP_TOKEN=""
            KEEP_ID=""
            if [ -f "$TG_CONFIG" ]; then
                KEEP_TOKEN=$(grep "TG_TOKEN" "$TG_CONFIG" | cut -d"'" -f2)
                KEEP_ID=$(grep "TG_ID" "$TG_CONFIG" | cut -d"'" -f2)
                echo -e "${GREEN}Current Bot Settings Saved!${NC}"
            fi

            # --- DOWNLOAD & RESTORE ---
            echo -e "${YELLOW}Downloading backup...${NC}"
            wget -O /root/backup.zip "$url"
            
            if unzip -t /root/backup.zip >/dev/null 2>&1; then
                echo -e "${GREEN}File valid! Restoring...${NC}"
                mkdir -p /etc/zivpn
                mkdir -p /etc/xray
                
                # Unzip & Overwrite
                cd /etc
                unzip -o /root/backup.zip
                
                # --- KEMBALIKAN CONFIG BOT LOKAL (JIKA ADA) ---
                if [ -n "$KEEP_TOKEN" ] && [ -n "$KEEP_ID" ]; then
                    echo "TG_TOKEN='$KEEP_TOKEN'" > "$TG_CONFIG"
                    echo "TG_ID='$KEEP_ID'" >> "$TG_CONFIG"
                    echo -e "${GREEN}Bot Token Restored from Current Server.${NC}"
                else
                    echo -e "${YELLOW}No local bot found. Using backup config.${NC}"
                fi

                # FIX PERMISSIONS
                chmod 755 /etc/zivpn
                chmod 644 /etc/zivpn/user.db
                chmod 644 /etc/xray/domain
                
                systemctl restart $SERVICE
                rm -f /root/backup.zip
                echo -e "${GREEN}Restore Success! User DB Updated.${NC}"
            else
                echo -e "${RED}Invalid Zip File / Link Expired!${NC}"
                rm -f /root/backup.zip
            fi
        else
            echo -e "${RED}URL cannot be empty!${NC}"
        fi
        read -n 1 -s -r -p "Press Enter to continue..."
    fi
}

function setup_telegram() {
    read -p "Bot Token: " t; read -p "Chat ID: " c
    echo "TG_TOKEN='$t'" > $TG_CONFIG; echo "TG_ID='$c'" >> $TG_CONFIG
    echo "Saved."; read -p "Enter..."
}

function set_backup_timer() {
    clear
    current=$(crontab -l | grep 'backup-tg' | awk '{print $2":"$1}')
    [ -z "$current" ] && current="Not Set"
    echo -e "${CYAN}┌──────────────────────────────────────────────┐${NC}\n${CYAN}│             SET AUTO BACKUP TIME             │${NC}\n${CYAN}└──────────────────────────────────────────────┘${NC}"
    echo -e " Current Schedule : ${GREEN}$current${NC}\n"
    read -p " Set Hour (0-23)   : " h
    read -p " Set Minute (0-59) : " m
    if [[ "$h" =~ ^[0-9]+$ ]] && [[ "$m" =~ ^[0-9]+$ ]]; then
        crontab -l | grep -v "backup-tg" | crontab -
        (crontab -l 2>/dev/null; echo "$m $h * * * /usr/local/bin/backup-tg") | crontab -
        service cron restart
        echo -e "\n${GREEN}✅ Auto Backup set to $h:$m daily.${NC}"
    else echo -e "\n${RED}❌ Invalid input.${NC}"; fi
    read -n 1 -s -r -p "Press Enter to continue..."
}

while true; do show_menu; done
END_OF_MENU
# --- INJECT URLS INTO MENU ---
sed -i "s|REPLACE_THIS_WITH_YOUR_REPO_URL|$REPO_URL|g" $MENU_BIN
chmod +x $MENU_BIN

    # --- 4. BACKUP SCRIPT (FULL DATA) ---
cat << 'EOF' > $BACKUP_BIN
#!/bin/bash
TG_CONFIG="/etc/zivpn/tg_backup.conf"
if [ ! -f "$TG_CONFIG" ]; then
    echo "Error: Telegram Config not found. Please run Setup Notif in Menu."
    exit 1
fi
source $TG_CONFIG

# Ensure ZIP installed
if ! command -v zip &> /dev/null; then apt-get install -y zip unzip >/dev/null 2>&1; fi

# Info
IP=$(curl -s ipv4.icanhazip.com)
DATE=$(date +%Y-%m-%d)
TIME=$(date +%H:%M)
DOMAIN=$(cat /etc/xray/domain 2>/dev/null || echo "No Domain")
ISP=$(curl -s ip-api.com/json | jq -r .isp)

# PREPARE BACKUP FOLDER
rm -rf /root/backup
mkdir -p /root/backup
# Copy Config & User DB
cp -r /etc/zivpn /root/backup/zivpn
# Copy Domain (Vital)
mkdir -p /root/backup/xray
cp /etc/xray/domain /root/backup/xray/domain 2>/dev/null

# ZIP
FILENAME="backup-${IP}-${DATE}.zip"
cd /root/backup
zip -r /root/$FILENAME . >/dev/null 2>&1
cd /root

# Check and Send
if [ -f "$FILENAME" ]; then
CAPTION="<b>✅ VPS DATA BACKUP</b>
━━━━━━━━━━━━━━━━━━━━
<b>IP     :</b> <code>${IP}</code>
<b>Domain :</b> <code>${DOMAIN}</code>
<b>ISP    :</b> <code>${ISP}</code>
<b>Date   :</b> <code>${DATE}</code>
<b>Time   :</b> <code>${TIME}</code>
━━━━━━━━━━━━━━━━━━━━
<i>Backup Database, Config & Domain</i>"

    # SENDING DOCUMENT (CURL -F)
    curl -s -F chat_id="$TG_ID" -F document=@"$FILENAME" -F caption="$CAPTION" -F parse_mode="html" "https://api.telegram.org/bot$TG_TOKEN/sendDocument" > /dev/null
    
    rm -rf /root/backup
    rm $FILENAME
    echo -e "Backup sent to Telegram."
else
    echo "Failed to create backup file."
fi
EOF
    chmod +x $BACKUP_BIN

    # --- CLEAN OLD BASHRC ---
    sed -i '/landing-page/d' /root/.bashrc
    
    # --- LANDING PAGE ---
    echo '[ -f /usr/bin/landing-page ] && . /usr/bin/landing-page' >> /root/.bashrc

    # Fix Landing Page Script
cat << 'EOF' > $LANDING_BIN
#!/bin/bash
NC='\033[0m'; PURPLE='\033[0;35m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; WHITE='\033[1;37m'; GREEN='\033[0;32m'; RED='\033[0;31m'; BLUE='\033[0;34m'
OS=$(lsb_release -d | cut -f2 | tr -d '"' | sed 's/Ubuntu //')
IP=$(curl -s ipv4.icanhazip.com)
DOMAIN=$(cat /etc/xray/domain 2>/dev/null || echo "No Domain")
JSON_IP=$(curl -s ip-api.com/json); ISP=$(echo "$JSON_IP" | jq -r .isp)
CLIENT=$(cat /etc/wintunnel/client 2>/dev/null || echo "User")
EXP_DATE=$(cat /etc/wintunnel/exp 2>/dev/null || echo "Lifetime")
RAM_USED=$(free -m | awk 'NR==2{print $3}')
RAM_TOTAL=$(free -m | awk 'NR==2{print $2}')
RAM_PERC=$(awk "BEGIN {printf \"%.0f\", $RAM_USED/$RAM_TOTAL*100}")
CPU_MODEL=$(lscpu | grep "Model name" | cut -d: -f2 | sed 's/^ //;s/  */ /g' | cut -c1-20)
CPU_CORES=$(nproc)
UPTIME=$(uptime -p | sed 's/up //')
USERS=$(wc -l < /etc/zivpn/user.db 2>/dev/null || echo "0")
API_KEY=$(cat /etc/zivpn/apikey 2>/dev/null)
INTF=$(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1)
BW_DAILY=$(vnstat -i $INTF -d --oneline | awk -F\; '{print $6}')
[ -z "$BW_DAILY" ] && BW_DAILY="0 B"
BW_MONTHLY=$(vnstat -i $INTF -m --oneline | awk -F\; '{print $6}')
[ -z "$BW_MONTHLY" ] && BW_MONTHLY="0 B"
if systemctl is-active --quiet zivpn; then STAT_VPN="${GREEN}ON${NC}"; else STAT_VPN="${RED}OFF${NC}"; fi
if systemctl is-active --quiet zivpn-api; then STAT_API="${GREEN}ON${NC}"; else STAT_API="${RED}OFF${NC}"; fi

clear
echo -e "${PURPLE} ╭────────────────────────────────────────────────${NC}"
echo -e "${PURPLE} │${CYAN}                WINTUNELING ZIVPN${NC}"
echo -e "${PURPLE} ├────────────────────────────────────────────────${NC}"
echo -e "${PURPLE} │${CYAN} OS      : ${WHITE}$OS${NC}"
echo -e "${PURPLE} │${CYAN} IP      : ${WHITE}$IP${NC}"
echo -e "${PURPLE} │${CYAN} Domain  : ${WHITE}$DOMAIN${NC}"
echo -e "${PURPLE} │${CYAN} ISP     : ${WHITE}$ISP${NC}"
echo -e "${PURPLE} ├─────────────────────────────────────────────────${NC}"
echo -e "${PURPLE} │${CYAN} Client  : ${WHITE}$CLIENT${NC}"
echo -e "${PURPLE} │${CYAN} Exp     : ${WHITE}$EXP_DATE${NC}"
echo -e "${PURPLE} ├─────────────────────────────────────────────────${NC}"
echo -e "${PURPLE} │${CYAN} RAM     : ${WHITE}$RAM_USED/$RAM_TOTAL MB ($RAM_PERC%)${NC}"
echo -e "${PURPLE} │${CYAN} CPU     :${WHITE}$CPU_MODEL ($CPU_CORES Core)${NC}"
echo -e "${PURPLE} │${CYAN} Uptime  : ${WHITE}$UPTIME${NC}"
echo -e "${PURPLE} │${CYAN} Users   : ${WHITE}$USERS Accounts${NC}"
echo -e "${PURPLE} ├─────────────────────────────────────────────────${NC}"
echo -e "${PURPLE} │${CYAN} Today   : ${WHITE}$BW_DAILY${NC}"
echo -e "${PURPLE} │${CYAN} Month   : ${WHITE}$BW_MONTHLY${NC}"
echo -e "${PURPLE} ├─────────────────────────────────────────────────${NC}"
echo -e "${PURPLE} │${CYAN} Service : ${STAT_VPN}    ${CYAN}API : ${STAT_API}${NC}   ${CYAN} API Key : ${YELLOW}$API_KEY${NC}"
echo -e "${PURPLE} ╰─────────────────────────────────────────────────${NC}"
echo -e ""
echo -e "  ${BLUE}[1]${NC} Create Account        ${BLUE}[2]${NC} Create Trial"
echo -e "  ${BLUE}[3]${NC} Renew Account         ${BLUE}[4]${NC} Delete Account"
echo -e "  ${BLUE}[5]${NC} List Accounts         ${BLUE}[6]${NC} Change Domain"
echo -e "  ${BLUE}[7]${NC} Backup/Restore        ${BLUE}[8]${NC} Setup Notif"
echo -e "  ${BLUE}[9]${NC} Restart Service       ${BLUE}[10]${NC} Generate API"
echo -e "  ${BLUE}[11]${NC} Cek Sertifikat       ${BLUE}[12]${NC} Set Auto Backup"
echo -e "  ${BLUE}[13]${NC} Update Script        ${BLUE}[0]${NC} Exit"
echo -e ""
echo -e "${CYAN}       >>> PRESS [ ENTER ] TO ENTER MENU <<<${NC}"
read -n 1 -s -r -p ""
menu
EOF
    chmod +x $LANDING_BIN

    # --- 5. FINALIZE UPDATE ---
    systemctl daemon-reload
    systemctl enable $SERVICE_VPN $SERVICE_API
    systemctl restart $SERVICE_VPN $SERVICE_API
}

# ==========================================
# 5. EXECUTION LOGIC (INSTALL OR UPDATE)
# ==========================================
if [ "$UPDATE_MODE" == "true" ]; then
    # Jika mode update, jalankan fungsi update_resources saja
    generate_core_files
    echo -e "${GREEN}Update Completed Successfully!${NC}"
    exit 0
else
    # Jika install baru, jalankan semua prosedur
    
    # LICENSE CHECK
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
            echo -e "${RED}            ⛔ LICENSE EXPIRED: $EXP_DATE${NC}"
            echo -e "${RED}    Please Contact Admin: t.me/WINTUNELING_VPN${NC}"
            echo -e "${GREEN}└──────────────────────────────────────────────────┘${NC}"
            exit 1
        else
            echo -e "${PURPLE}┌──────────────────────────────────────────────────┐${NC}"
            echo -e "${GREEN}            ✅ LICENSE ACTIVE! ($CLIENT_NAME)${NC}"
            echo -e "${GREEN}           THANKS FOR USING THIS SCRIPT${NC}"
            echo -e "${PURPLE}└──────────────────────────────────────────────────┘${NC}"
            mkdir -p /etc/wintunnel
            echo "$CLIENT_NAME" > /etc/wintunnel/client
            echo "$EXP_DATE" > /etc/wintunnel/exp
            sleep 1
        fi
    else
        echo -e "${GREEN}┌──────────────────────────────────────────────────┐${NC}"
        echo -e "${RED}                ⛔ ACCESS DENIED!${NC}"
        echo -e "${RED}    Please Contact Admin: t.me/WINTUNELING_VPN${NC}"
        echo -e "${GREEN}└──────────────────────────────────────────────────┘${NC}"
        exit 1
    fi

    # SYSTEM PREP
    echo -e "${CYAN}[1/5] System Setup...${NC}"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y >/dev/null 2>&1
    apt-get install -y curl wget jq openssl zip unzip cron net-tools lsb-release gnupg vnstat bc neofetch iptables-persistent netfilter-persistent >/dev/null 2>&1

    # KERNEL TUNING
    cat >> /etc/sysctl.conf <<EOF
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.udp_rmem_min=8192
net.ipv4.udp_wmem_min=8192
EOF
    sysctl -p >/dev/null 2>&1

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

    # DOMAIN SETUP
    clear
    echo -e "${GREEN}┌──────────────────────────────────────────────────┐${NC}"
    echo -e "${YELLOW}             ISI DOMAIN SERVER ANDA              ${NC}"
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

    # CERT GENERATION
    rm -rf $DIR/zivpn.key $DIR/zivpn.crt
    openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 -subj "/C=ID/CN=$DOMAIN_INPUT" -keyout "$DIR/zivpn.key" -out "$DIR/zivpn.crt" >/dev/null 2>&1

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

    # EXECUTE CORE FILES GENERATOR
    generate_core_files

    # IPTABLES
    iptables -t nat -A PREROUTING -i $INTF -p udp --dport 6000:19999 -j DNAT --to-destination :5667
    netfilter-persistent save >/dev/null 2>&1

    # AUTO BACKUP DEFAULT
    crontab -l | grep -v "backup-tg" | crontab -
    (crontab -l 2>/dev/null; echo "0 0 * * * /usr/local/bin/backup-tg") | crontab -
    service cron restart

    # CLEAN AND INJECT BASHRC (FIX LOOP)
    sed -i '/landing-page/d' /root/.bashrc
    echo '[ -f /usr/bin/landing-page ] && . /usr/bin/landing-page' >> /root/.bashrc

    clear
    echo -e "${GREEN}┌──────────────────────────────────────────────────┐${NC}"
    echo -e "${YELLOW}             SUCCESFULLY INSTALL SCRIPT            ${NC}"
    echo -e "${GREEN}└──────────────────────────────────────────────────┘${NC}"
    echo -e " Wait for 5s server will automatically rebooting"
    echo -e " Rebooting in 5s..."
    sleep 5
    reboot
fi