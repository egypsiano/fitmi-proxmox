#!/usr/bin/env bash

source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func) 

# Copyright (c) 2025 egypsiano
# Author: havardthom
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE   
# Source: https://openwebui.com/ 

APP="FitMe Prox"
var_tags="${var_tags:-fitness;workout}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

TELEGRAM_BOT_TOKEN="7937344020:AAEKyykBOWSmXibUf1UBMj4Drvfu3LeKSY4"
CHAT_ID="RediFitmiBot"

header_info "$APP"
variables
color
catch_errors

function telegram_notify() {
  if [[ -z "$TELEGRAM_BOT_TOKEN" || -z "$CHAT_ID" ]]; then
    echo "Telegram notification skipped: missing token or chat ID."
    return
  fi

  curl -s -X POST https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage  \
    -d chat_id=$CHAT_ID \
    -d text="$1"
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/fitme-proxmox ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating ${APP} (Patience)"
  cd /opt/fitme-proxmox

  # Backup existing data before updating
  mkdir -p /opt/fitme-proxmox-backup
  cp -rf /opt/fitme-proxmox/data /opt/fitme-proxmox-backup

  # Pull latest changes from Git
  git add -A
  $STD git stash
  $STD git reset --hard
  output=$(git pull --no-rebase)
  if echo "$output" | grep -q "Already up to date."; then
    msg_ok "${APP} is already up to date."
    exit
  fi

  systemctl stop fitme-proxmox.service || true
  $STD docker-compose build
  $STD docker-compose down
  $STD docker-compose up -d

  # Restore user data
  cp -rf /opt/fitme-proxmox-backup/* /opt/fitme-proxmox/data

  # Pop any stashed changes
  if git stash list | grep -q 'stash@{'; then
    $STD git stash pop
  fi

  systemctl start fitme-proxmox.service || true
  telegram_notify "🔄 $APP was updated successfully on http://$IP:3000"
  msg_ok "Updated Successfully"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"

telegram_notify "✅ $APP was deployed successfully on http://$IP:3000"