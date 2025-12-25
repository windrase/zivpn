#!/bin/bash
# ============================================================
# SCRIPT UPDATE MENU & WELCOME (CLEAN LAYOUT)
# ============================================================

# --- Variables ---
MENU_BIN="/usr/local/bin/menu"
WELCOME_BIN="/usr/local/bin/welcome"
DIR="/etc/zivpn"

# --- Warna ---
CYAN='\e[1;36m'
YELLOW='\e[1;33m'
GREEN='\e[1;32m'
RED='\e[1;31m'
NC='\e[0m'
GRAY='\e[90m'

echo -e "${YELLOW}[INFO] Updating Menu & Welcome Page...${NC}"

# ============================================================
# 1. UPDATE FILE: WELCOME (PREVIEW) - LAYOUT FIX
# ============================================================
echo -e "${CYAN}[1/3] Installing Clean Welcome Page...${NC}"
cat << 'END_WELCOME' > $WELCOME_BIN
#!/bin/bash
# WINTUNELING PREVIEW (CLEAN LAYOUT)
NC='\e[0m'
CYAN='\e[1;36m'
WHITE='\e[1;37m'
GREEN='\e[1;32m'
YELLOW='\e[1;33m'
RED='\e[1;31m'
GRAY='\e[90m'

function get_info_preview() {
    # 1. OS & IP
    if [ -f /etc/os-release ]; then . /etc/os-release; OS_NAME=$NAME; else OS_NAME=$(lsb_release -d | cut -f2 | tr -d '"' | sed 's/Ubuntu //'); fi
    OS_NAME=$(echo "$OS_NAME" | cut -c 1-18)
    IP=$(curl -s ipv4.icanhazip.com)
    ISP=$(curl -s ip-api.com/json | jq -r .isp | cut -c 1-18)
    
    # 2. LICENSE
    CLIENT=$(cat /etc/wintunnel/client 2>/dev/null || echo "Unknown")
    EXP_DATE=$(cat /etc/wintunnel/exp 2>/dev/null || echo "Unknown")
    d1=$(date -d "$EXP_DATE" +%s 2>/dev/null)
    d2=$(date -d "$(date +%Y-%m-%d)" +%s)
    if [[ ! -z "$d1" ]]; then
        DAYS_LEFT=$(( ($d1 - $d2) / 86400 ))
        [ $DAYS_LEFT -lt 0 ] && DAYS_LEFT="EXPIRED"
    else
        DAYS_LEFT="-"
    fi

    # 3. RAM & CPU
    used_ram=$(free -m | awk 'NR==2{print $3}')
    total_ram=$(free -m | awk 'NR==2{print $2}')
    ram_perc=$(awk "BEGIN {printf \"%.0f\", $used_ram/$total_ram*100}")
    cpu_usage=$(grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5)} END {print usage}' | awk '{printf("%.0f", $1)}')
    
    # 4. BANDWIDTH
    INTF=$(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1)
    RX_TODAY=$(vnstat -i $INTF -d --oneline 2>/dev/null | awk -F\; '{print $6}')
    TX_TODAY=$(vnstat -i $INTF -d --oneline 2>/dev/null | awk -F\; '{print $7}')
    [ -z "$RX_TODAY" ] && RX_TODAY="0 B"
    [ -z "$TX_TODAY" ] && TX_TODAY="0 B"
}

clear
get_info_preview

# --- FUNGSI PRINT RAPI (Auto Padding) ---
# Lebar konten dalam box = 56 char
# Garis: ╭ (1) + 56 (─) + ╮ (1) = 58 Total

function print_line() {
    # $1 = Label Kiri, $2 = Value Kiri, $3 = Label Kanan, $4 = Value Kanan
    # Format: " L_LABEL : L_VAL    R_LABEL : R_VAL "
    # Split 56 chars: Left 27, Right 27, Spacing 2?
    # Kita pakai printf fix width
    
    # Construct String Kiri (Max 26 char)
    LEFT_TXT="$1: $2"
    if [ ${#LEFT_TXT} -gt 26 ]; then LEFT_TXT="${LEFT_TXT:0:26}"; fi
    
    # Construct String Kanan (Max 26 char)
    RIGHT_TXT="$3: $4"
    if [ ${#RIGHT_TXT} -gt 26 ]; then RIGHT_TXT="${RIGHT_TXT:0:26}"; fi
    
    printf "${CYAN} │${NC} ${GRAY}%-26s${NC}  ${GRAY}%-26s${NC} ${CYAN}│${NC}\n" "$LEFT_TXT" "$RIGHT_TXT"
}

# --- TAMPILAN ---
echo -e "${CYAN} ╭────────────────────────────────────────────────────────╮${NC}"
echo -e "${CYAN} │${WHITE}                   WINTUNELING ZIVPN                    ${NC}${CYAN}│${NC}"
echo -e "${CYAN} ╰────────────────────────────────────────────────────────╯${NC}"

echo -e "${CYAN} ╭──────────────────────${WHITE} SYSTEM ${CYAN}──────────────────────────╮${NC}"
print_line "OS" "$OS_NAME" "RAM" "$used_ram MB ($ram_perc%)"
print_line "IP" "$IP" "CPU" "$cpu_usage %"
print_line "ISP" "$ISP" "VPN" "ON RUNNING"
echo -e "${CYAN} ├────────────────────────────────────────────────────────┤${NC}"
print_line "BW Today" "↓$RX_TODAY" "↑$TX_TODAY" ""
echo -e "${CYAN} ╰────────────────────────────────────────────────────────╯${NC}"

echo -e "${CYAN} ╭──────────────────────${WHITE} LICENSE ${CYAN}─────────────────────────╮${NC}"
# Custom Print untuk License agar lebar
L_CLIENT="Client : $CLIENT"
L_EXP="Expired: $EXP_DATE ($DAYS_LEFT Days)"
printf "${CYAN} │${NC} ${YELLOW}%-54s${NC} ${CYAN}│${NC}\n" "${L_CLIENT:0:54}"
printf "${CYAN} │${NC} ${WHITE}%-54s${NC} ${CYAN}│${NC}\n" "${L_EXP:0:54}"
echo -e "${CYAN} ╰────────────────────────────────────────────────────────╯${NC}"

echo -e "${CYAN} ╭──────────────────────${WHITE} ACCOUNT ${CYAN}─────────────────────────╮${NC}"
printf "${CYAN} │${NC} ${WHITE}[1]${NC} %-23s ${WHITE}[2]${NC} %-23s ${CYAN}│${NC}\n" "Create Account" "Create Trial"
printf "${CYAN} │${NC} ${WHITE}[3]${NC} %-23s ${WHITE}[4]${NC} %-23s ${CYAN}│${NC}\n" "Renew Account" "Delete Account"
printf "${CYAN} │${NC} ${WHITE}[5]${NC} %-23s ${WHITE}[6]${NC} %-23s ${CYAN}│${NC}\n" "List Users" "Change Domain"
echo -e "${CYAN} ╰────────────────────────────────────────────────────────╯${NC}"

echo -e "${CYAN} ╭──────────────────────${WHITE} SETTINGS ${CYAN}────────────────────────╮${NC}"
printf "${CYAN} │${NC} ${WHITE}[7]${NC} %-23s ${WHITE}[8]${NC} %-23s ${CYAN}│${NC}\n" "Restart Service" "Setup Telegram"
printf "${CYAN} │${NC} ${WHITE}[9]${NC} %-23s ${WHITE}[10]${NC} %-22s ${CYAN}│${NC}\n" "Backup Now" "Auto Backup"
printf "${CYAN} │${NC} ${WHITE}[11]${NC} %-49s ${CYAN}│${NC}\n" "Restore Data"
echo -e "${CYAN} ╰────────────────────────────────────────────────────────╯${NC}"

echo -e "                         ${RED}[0] Exit${NC}"
echo -e ""
read -n 1 -s -r -p "             Tekan [ ENTER ] untuk masuk ke Menu..."

# Masuk Menu Asli
menu
END_WELCOME
chmod +x $WELCOME_BIN


# ============================================================
# 2. UPDATE FILE: MENU UTAMA (SAMAKAN LAYOUT)
# ============================================================
echo -e "${CYAN}[2/3] Updating Main Menu...${NC}"
cat << 'END_OF_MENU' > $MENU_BIN
#!/bin/bash
# WINTUNELING MENU - PROFESSIONAL EDITION

DIR="/etc/zivpn"
DB="$DIR/user.db"
CONFIG="$DIR/config.json"
SERVICE="zivpn"

# Warna
CYAN='\e[1;36m'
WHITE='\e[1;37m'
GREEN='\e[1;32m'
YELLOW='\e[1;33m'
RED='\e[1;31m'
NC='\e[0m'
GRAY='\e[90m'

function get_info() {
    if [ -f /etc/os-release ]; then . /etc/os-release; OS_NAME=$NAME; else OS_NAME=$(lsb_release -d | cut -f2 | tr -d '"' | sed 's/Ubuntu //'); fi
    OS_NAME=$(echo "$OS_NAME" | cut -c 1-18)
    IP=$(curl -s ipv4.icanhazip.com)
    ISP=$(curl -s ip-api.com/json | jq -r .isp | cut -c 1-18)
    
    CLIENT=$(cat /etc/wintunnel/client 2>/dev/null || echo "Unknown")
    EXP_DATE=$(cat /etc/wintunnel/exp 2>/dev/null || echo "Unknown")
    d1=$(date -d "$EXP_DATE" +%s 2>/dev/null)
    d2=$(date -d "$(date +%Y-%m-%d)" +%s)
    if [[ ! -z "$d1" ]]; then
        DAYS_LEFT=$(( ($d1 - $d2) / 86400 ))
        [ $DAYS_LEFT -lt 0 ] && DAYS_LEFT="EXPIRED"
    else
        DAYS_LEFT="-"
    fi

    used_ram=$(free -m | awk 'NR==2{print $3}')
    total_ram=$(free -m | awk 'NR==2{print $2}')
    ram_perc=$(awk "BEGIN {printf \"%.0f\", $used_ram/$total_ram*100}")
    cpu_usage=$(grep 'cpu ' /proc/stat | awk '{usage=($2+$4)*100/($2+$4+$5)} END {print usage}' | awk '{printf("%.0f", $1)}')
    
    INTF=$(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1)
    RX_TODAY=$(vnstat -i $INTF -d --oneline 2>/dev/null | awk -F\; '{print $6}')
    TX_TODAY=$(vnstat -i $INTF -d --oneline 2>/dev/null | awk -F\; '{print $7}')
    [ -z "$RX_TODAY" ] && RX_TODAY="0 B"
    [ -z "$TX_TODAY" ] && TX_TODAY="0 B"
}

function print_line() {
    LEFT_TXT="$1: $2"
    if [ ${#LEFT_TXT} -gt 26 ]; then LEFT_TXT="${LEFT_TXT:0:26}"; fi
    RIGHT_TXT="$3: $4"
    if [ ${#RIGHT_TXT} -gt 26 ]; then RIGHT_TXT="${RIGHT_TXT:0:26}"; fi
    printf "${CYAN} │${NC} ${GRAY}%-26s${NC}  ${GRAY}%-26s${NC} ${CYAN}│${NC}\n" "$LEFT_TXT" "$RIGHT_TXT"
}

function show_menu() {
    clear
    get_info
    echo -e "${CYAN} ╭────────────────────────────────────────────────────────╮${NC}"
    echo -e "${CYAN} │${WHITE}                   WINTUNELING ZIVPN                    ${NC}${CYAN}│${NC}"
    echo -e "${CYAN} ╰────────────────────────────────────────────────────────╯${NC}"

    echo -e "${CYAN} ╭──────────────────────${WHITE} SYSTEM ${CYAN}──────────────────────────╮${NC}"
    print_line "OS" "$OS_NAME" "RAM" "$used_ram MB ($ram_perc%)"
    print_line "IP" "$IP" "CPU" "$cpu_usage %"
    print_line "ISP" "$ISP" "VPN" "ON RUNNING"
    echo -e "${CYAN} ├────────────────────────────────────────────────────────┤${NC}"
    print_line "BW Today" "↓$RX_TODAY" "↑$TX_TODAY" ""
    echo -e "${CYAN} ╰────────────────────────────────────────────────────────╯${NC}"

    echo -e "${CYAN} ╭──────────────────────${WHITE} LICENSE ${CYAN}─────────────────────────╮${NC}"
    L_CLIENT="Client : $CLIENT"
    L_EXP="Expired: $EXP_DATE ($DAYS_LEFT Days)"
    printf "${CYAN} │${NC} ${YELLOW}%-54s${NC} ${CYAN}│${NC}\n" "${L_CLIENT:0:54}"
    printf "${CYAN} │${NC} ${WHITE}%-54s${NC} ${CYAN}│${NC}\n" "${L_EXP:0:54}"
    echo -e "${CYAN} ╰────────────────────────────────────────────────────────╯${NC}"

    echo -e "${CYAN} ╭──────────────────────${WHITE} ACCOUNT ${CYAN}─────────────────────────╮${NC}"
    printf "${CYAN} │${NC} ${WHITE}[1]${NC} %-23s ${WHITE}[2]${NC} %-23s ${CYAN}│${NC}\n" "Create Account" "Create Trial"
    printf "${CYAN} │${NC} ${WHITE}[3]${NC} %-23s ${WHITE}[4]${NC} %-23s ${CYAN}│${NC}\n" "Renew Account" "Delete Account"
    printf "${CYAN} │${NC} ${WHITE}[5]${NC} %-23s ${WHITE}[6]${NC} %-23s ${CYAN}│${NC}\n" "List Users" "Change Domain"
    echo -e "${CYAN} ╰────────────────────────────────────────────────────────╯${NC}"

    echo -e "${CYAN} ╭──────────────────────${WHITE} SETTINGS ${CYAN}────────────────────────╮${NC}"
    printf "${CYAN} │${NC} ${WHITE}[7]${NC} %-23s ${WHITE}[8]${NC} %-23s ${CYAN}│${NC}\n" "Restart Service" "Setup Telegram"
    printf "${CYAN} │${NC} ${WHITE}[9]${NC} %-23s ${WHITE}[10]${NC} %-22s ${CYAN}│${NC}\n" "Backup Now" "Auto Backup"
    printf "${CYAN} │${NC} ${WHITE}[11]${NC} %-49s ${CYAN}│${NC}\n" "Restore Data"
    echo -e "${CYAN} ╰────────────────────────────────────────────────────────╯${NC}"
    
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
        7) systemctl restart $SERVICE; echo -e "${GREEN}Service Restarted.${NC}"; sleep 1 ;;
        8) setup_telegram_notif ;;
        9) backup_data ;;
        10) auto_backup_setup ;;
        11) restore_data ;;
        0) exit 0 ;;
    esac
}

# --- FUNGSI LOGIC (Placeholder agar script jalan) ---
function create_user() { echo "Create User..."; sleep 1; }
function trial_user() { echo "Trial User..."; sleep 1; }
function renew_user() { echo "Renew User..."; sleep 1; }
function delete_user() { echo "Delete User..."; sleep 1; }
function list_user() { echo "List User..."; sleep 1; }
function change_domain() { echo "Change Domain..."; sleep 1; }
function setup_telegram_notif() { echo "Setup Telegram..."; sleep 1; }
function backup_data() { echo "Backup..."; sleep 1; }
function auto_backup_setup() { echo "Auto Backup..."; sleep 1; }
function restore_data() { echo "Restore..."; sleep 1; }

while true; do show_menu; done
END_OF_MENU
chmod +x $MENU_BIN

echo -e "${CYAN}[3/3] Checking Auto-Start...${NC}"
if ! grep -q "welcome" ~/.bashrc; then
    echo "" >> ~/.bashrc
    echo "# Auto Run Welcome Preview" >> ~/.bashrc
    echo "if [[ -n \"\$SSH_CLIENT\" ]] || [[ -n \"\$SSH_TTY\" ]]; then" >> ~/.bashrc
    echo "    $WELCOME_BIN" >> ~/.bashrc
    echo "fi" >> ~/.bashrc
fi

echo -e "${GREEN}✅ Update Selesai!${NC}"
echo -e "Ketik ${BOLD}menu${NC} atau login ulang VPS untuk melihat hasilnya."
