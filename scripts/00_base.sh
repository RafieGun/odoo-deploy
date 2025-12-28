#!/bin/bash
set -e

echo "🧱 [00] Base system setup"

# Timezone
timedatectl set-timezone Asia/Jakarta

# Update OS
apt update -y
apt upgrade -y

# Basic packages
apt install -y \
  curl \
  wget \
  git \
  ca-certificates \
  gnupg \
  lsb-release \
  software-properties-common \
  unzip \
  ufw

# Firewall
ufw allow OpenSSH
ufw allow 80
ufw allow 443
ufw --force enable

echo "✅ Base system ready"
