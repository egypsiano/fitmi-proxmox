#!/bin/bash

# ============ Internal Functions ============
function variables() {
    var_os=${var_os:-debian}
    var_version=${var_version:-12}
    var_unprivileged=${var_unprivileged:-1}
    var_cpu=${var_cpu:-4}
    var_ram=${var_ram:-8192}
    var_disk=${var_disk:-20}
}

function color() {
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    NC='\033[0m'
    BOLDGREEN='\033[1;32m'
    BOLDRED='\033[1;31m'
}

function header_info() {
    echo -e "\n\n${BOLDGREEN}== $* ==${NC}\n"
}

function msg_ok() {
    echo -e "${GREEN}$*${NC}"
}

function msg_error() {
    echo -e "${RED}$*${NC}"
    exit 1
}

function catch_errors() {
    trap 'msg_error "An error occurred during deployment.";' ERR
}

# ============ Variables ============
APP="FitMe Prox"
TELEGRAM_BOT_TOKEN="7937344020:AAEKyykBOWSmXibUf1UBMj4Drvfu3LeKSY4"
CHAT_ID="RediFitmiBot"

variables
color
catch_errors
header_info "$APP"

# ============ Telegram Notification ============
function telegram_notify() {
  if [[ -z "$TELEGRAM_BOT_TOKEN" || -z "$CHAT_ID" ]]; then
    echo "Telegram notification skipped: missing token or chat ID."
    return
  fi

  curl -s -X POST https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage  \
    -d chat_id=$CHAT_ID \
    -d text="$1"
}

# ============ Main Deployment ============
CONTAINER_ID=100
CONTAINER_NAME="fitme-proxmox"
OSTEMPLATE="debian:bookworm"
IS_PRIVILEGED=true
DISK_SIZE="20G"
BRIDGE="vmbr0"
IP_METHOD="dhcp"
IP_ADDRESS=""
DNS_SERVERS=("8.8.8.8" "8.8.4.4")
ROOT_PASSWORD=""

# ============ Wizard Steps ============
echo "🚀 Welcome to the FitMe Prox Deployment Wizard"

# Choose Container ID
read -p "Enter container ID [default: $CONTAINER_ID]: " input
CONTAINER_ID=${input:-$CONTAINER_ID}

# Choose OS Template
read -p "Choose OS template [default: $OSTEMPLATE]: " input
OSTEMPLATE=${input:-$OSTEMPLATE}

# Choose Privileged or Unprivileged
read -p "Should the container be privileged? [y/n] (default: y): " answer
IS_PRIVILEGED=$(echo "$answer" | tr '[:upper:]' '[:lower:]')
IS_PRIVILEGED=${IS_PRIVILEGED:-yes}

# Set Root Password
while true; do
  read -p "Enter root password for the container: " ROOT_PASSWORD
  read -p "Re-enter root password: " CONFIRM_PASSWORD
  if [[ "$ROOT_PASSWORD" == "$CONFIRM_PASSWORD" ]]; then
    break
  else
    msg_error "Passwords do not match. Please try again."
  fi
done

# Create LXC Container
qm create "$CONTAINER_ID" \
  --name "$CONTAINER_NAME" \
  --ostemplate "$OSTEMPLATE" \
  --memory "$var_ram" \
  --swap 512 \
  --rootfs local-lvm:$DISK_SIZE \
  --net0 name=eth0,bridge=$BRIDGE,model=virtio \
  --ipconfig0 ip="$IP_ADDRESS",gw="192.168.1.1",dns="${DNS_SERVERS[*]}" \
  --unprivileged $([[ "$IS_PRIVILEGED" == "no" ]] && echo "1" || echo "0") || msg_error "Failed to create container."

# Set root password
qm set "$CONTAINER_ID" --password "$ROOT_PASSWORD" || msg_error "Failed to set root password."

# Start container
qm start "$CONTAINER_ID" || msg_error "Failed to start container."

# Wait until online
until ping -c 1 "$IP_ADDRESS" &> /dev/null; do
  echo -n "."
  sleep 1
done
echo -e "\nContainer is online!"

# Install dependencies and deploy app
sshpass -p "$ROOT_PASSWORD" ssh -o StrictHostKeyChecking=no root@$IP_ADDRESS << EOF
set -e

apt update && apt upgrade -y
apt install -y sudo git curl wget gnupg lsb-release

curl -fsSL https://download.docker.com/linux/debian/gpg  | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian  $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

apt update
apt install -y docker-ce docker-ce-cli containerd.io

systemctl enable docker
systemctl start docker

APP_DIR="/opt/fitme-proxmox"
GIT_REPO="https://github.com/egypsiano/fitme-proxmox.git" 

git clone "$GIT_REPO" "$APP_DIR"
cd "$APP_DIR"

docker-compose build
docker-compose up -d

echo "✅ Deployment complete. Access your app at http://$IP_ADDRESS:3000"
EOF

# Send Telegram notification
telegram_notify "✅ $APP was deployed successfully on http://$IP_ADDRESS:3000"

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GREEN}${APP} setup has been successfully initialized!${NC}"
echo -e "${INFO}${YELLOW} Access it using the following URL:${NC}"
echo -e "${TAB}${GREEN}http://${IP_ADDRESS}:3000${NC}"

exit 0