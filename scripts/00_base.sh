#!/bin/bash
set -e

echo "🧱 [00] Base system setup"

# ===== TIMEZONE =====
timedatectl set-timezone Asia/Jakarta

# ===== UPDATE OS =====
apt update -y
apt upgrade -y

# ===== BASIC PACKAGES =====
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

# ===== FIREWALL =====
ufw allow OpenSSH
ufw allow 80
ufw allow 443
ufw --force enable

echo "✅ Base system ready"
