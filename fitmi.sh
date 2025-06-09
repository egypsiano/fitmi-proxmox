#!/bin/bash

# ============ Variables ============
CONTAINER_ID=100
CONTAINER_NAME="workout-platform"
OSTEMPLATE="debian:bookworm"  # You can change to "ubuntu:jammy"
IP_ADDRESS="192.168.1.100"    # Change to your desired IP
SSH_USER="root"
APP_DIR="/root/workout-platform"
GIT_REPO="https://github.com/yourusername/workout-platform.git" 

# ============ Functions ============
info() {
  printf "\n\n\e[34m%s\e[0m\n\n" "$*"
}

success() {
  printf "\n\n\e[32m%s\e[0m\n\n" "$*"
}

error() {
  printf "\n\n\e[31m%s\e[0m\n\n" "$*"
  exit 1
}

# ============ Main Script ============
info "🚀 Starting Proxmox Deployment for Workout Platform..."

# Step 1: Create LXC Container
info "Creating LXC container with ID $CONTAINER_ID..."
qm create "$CONTAINER_ID" --name "$CONTAINER_NAME" --ostemplate "$OSTEMPLATE" --memory 2048 --swap 512 --net0 name=eth0,bridge=vmbr0,ip="$IP_ADDRESS"/24,model=virtio || error "Failed to create container."

# Step 2: Start the Container
info "Starting container..."
qm start "$CONTAINER_ID" || error "Failed to start container."

# Step 3: Wait until it's online
info "Waiting for container to be reachable at $IP_ADDRESS..."
until ping -c 1 "$IP_ADDRESS" &> /dev/null; do
  echo -n .
  sleep 1
done
echo -e "\nContainer is online!"

# Step 4: Install Dependencies in Container
info "Installing dependencies inside container..."
ssh -o StrictHostKeyChecking=no "$SSH_USER@$IP_ADDRESS" << EOF
set -e

# Update and install basics
apt update && apt upgrade -y
apt install -y sudo git curl wget gnupg lsb-release

# Add Docker GPG key and repository
curl -fsSL https://download.docker.com/linux/debian/gpg  | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian  $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

# Install Docker
apt update
apt install -y docker-ce docker-ce-cli containerd.io

# Enable and start Docker
systemctl enable docker
systemctl start docker

# Clone your repo
git clone "$GIT_REPO" "$APP_DIR"

# Navigate to project directory
cd "$APP_DIR"

# Build and run Docker Compose
docker-compose build
docker-compose up -d

# Success message
echo "✅ Deployment complete. Access your app at http://$IP_ADDRESS"
EOF

# Done
success "🎉 Deployment completed successfully!"
success "Access your app at: http://$IP_ADDRESS"