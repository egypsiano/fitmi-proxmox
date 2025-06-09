#!/bin/bash

# Set variables
CONTAINER_ID=100
CONTAINER_NAME="workout-platform"
IMAGE="debian:bookworm"  # or "ubuntu:jammy"
IP_ADDRESS="192.168.1.100"  # Change to your desired IP
SSH_USER="root"
APP_DIR="/root/workout-platform"
GIT_REPO="https://github.com/yourusername/workout-platform.git" 

echo "🚀 Starting Proxmox Deployment Script..."

# Step 1: Create Privileged LXC Container
echo "Creating LXC container..."
qm create $CONTAINER_ID --name $CONTAINER_NAME --ostemplate $IMAGE --memory 2048 --swap 512 --net0 name=eth0,bridge=vmbr0,ip=$IP_ADDRESS/24,model=virtio

# Step 2: Start Container
echo "Starting container..."
qm start $CONTAINER_ID

# Step 3: Wait until it's online
until ping -c 1 $IP_ADDRESS &> /dev/null; do
    echo "Waiting for container to be reachable at $IP_ADDRESS..."
    sleep 5
done

echo "Container is online!"

# Step 4: Install required packages in container
ssh -o StrictHostKeyChecking=no $SSH_USER@$IP_ADDRESS << EOF
set -e

echo "Updating system..."
apt update && apt upgrade -y

echo "Installing necessary tools..."
apt install -y sudo git curl wget gnupg lsb-release

echo "Adding Docker repository..."
curl -fsSL https://download.docker.com/linux/debian/gpg  | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian  $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

echo "Installing Docker..."
apt update
apt install -y docker-ce docker-ce-cli containerd.io

echo "Enabling and starting Docker service..."
systemctl enable docker
systemctl start docker

echo "Cloning your workout-platform repo..."
git clone $GIT_REPO $APP_DIR

echo "Navigating to project directory..."
cd $APP_DIR

echo "Building and running Docker Compose..."
docker-compose build
docker-compose up -d

echo "✅ Done! Access your app at http://$IP_ADDRESS"
EOF

echo "🎉 Deployment completed successfully!"
echo "Access your app at: http://$IP_ADDRESS"
