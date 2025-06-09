#!/bin/bash
source <(curl -fsSL https://github.com/egypsiano/fitmi-proxmox/raw/refs/heads/main/build.func)
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
    YELLOW='\033[0;33m'
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

variables
color
catch_errors
header_info "FitMe Prox"

APP="FitMe Prox"
TELEGRAM_BOT_TOKEN="token"
CHAT_ID="id"

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

# ============ Variables ============
CONTAINER_NAME="fitme-proxmox"
OSTEMPLATE="debian/bookworm/amd64"
IS_PRIVILEGED=true
ROOT_PASSWORD="000000"
IP_ADDRESS="192.168.1.100"
BRIDGE="vmbr0"
DISK_SIZE="20G"
RAM_SIZE="8192"
CPU_CORES="4"

# ============ Wizard Steps ============
echo "🚀 Welcome to the FitMe Prox Deployment Wizard"

read -p "Enter container ID [default: 100]: " input
CONTAINER_ID=${input:-100}

read -p "Should the container be privileged? [y/n] (default: y): " answer
IS_PRIVILEGED=$(echo "$answer" | tr '[:upper:]' '[:lower:]')
IS_PRIVILEGED=${IS_PRIVILEGED:-yes}

read -p "Enter root password for the container: " ROOT_PASSWORD
read -p "Re-enter root password: " CONFIRM_PASSWORD
if [[ "$ROOT_PASSWORD" != "$CONFIRM_PASSWORD" ]]; then
    msg_error "Passwords do not match. Please try again."
fi

# ============ Check If Container Already Exists ============
if pct list | grep -q "$CONTAINER_ID"; then
    echo -e "${YELLOW}⚠️ A container with ID '$CONTAINER_ID' already exists.${NC}"
    read -p "Would you like to remove it and recreate it? [y/n]: " choice
    case "$choice" in
        y|Y) 
            pct stop "$CONTAINER_ID" || true
            pct destroy "$CONTAINER_ID" || true
            rm -f /etc/pve/lxc/"$CONTAINER_ID".conf || true
            echo "Removed existing container."
            ;;
        n|N)
            msg_error "Deployment cancelled. Choose another container ID or remove the existing one manually."
            ;;
        *) 
            msg_error "Invalid choice. Deployment cancelled."
            ;;
    esac
fi

# ============ Create Container (Proxmox 8.x compatible) ============
header_info "Creating LXC Container..."

# Create the container using lxc-create
lxc-create -n "$CONTAINER_NAME" -t download -- --dist debian --release bookworm --arch amd64 || msg_error "Failed to create container."

# Get the container ID from its name
CONTAINER_ID=$(pct list | grep "$CONTAINER_NAME" | awk '{print $1}')

# Set basic resources via pct
pct set "$CONTAINER_ID" --memory "$RAM_SIZE" --swap 512 --cores "$CPU_CORES" || msg_error "Failed to set container resources."

# Set network bridge and IP manually in config
echo "Configuring networking..."
cat <<EOF >> /etc/pve/lxc/$CONTAINER_ID.conf
lxc.network.type = veth
lxc.network.link = $BRIDGE
lxc.network.flags = up
lxc.network.hwaddr = $(openssl rand -hex 6 | sed 's/\(..\)/\1:/g; s/.$//')
lxc.network.ipv4 = $IP_ADDRESS/24
lxc.network.ipv4.gateway = 192.168.1.1
lxc.network.ipv4.dns = 8.8.8.8,8.8.4.4
EOF

# Set unprivileged mode in config
echo "Setting unprivileged mode..."
sed -i '/^lxc.idmap/d' /etc/pve/lxc/$CONTAINER_ID.conf
cat <<EOF >> /etc/pve/lxc/$CONTAINER_ID.conf
lxc.idmap = u 0 100000 65536
lxc.idmap = g 0 100000 65536
EOF

# Start container
lxc-start -n "$CONTAINER_NAME" || msg_error "Failed to start container."

# Wait until online
until ping -c 1 "$IP_ADDRESS" &> /dev/null; do
  echo -n "."
  sleep 1
done
echo -e "\nContainer is online!"

# ============ Install App Inside Container ============
sshpass -p "$ROOT_PASSWORD" ssh -o StrictHostKeyChecking=no root@$IP_ADDRESS << EOF
set -e

# Set root password
echo "root:$ROOT_PASSWORD" | chpasswd

apt update && apt upgrade -y
apt install -y sudo git curl wget gnupg lsb-release openssh-server

systemctl enable ssh
systemctl restart ssh

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
