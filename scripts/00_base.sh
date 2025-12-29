#!/bin/bash
set -e

echo "🧱 [00] Base system & dependencies"

apt update -y
apt upgrade -y

apt install -y \
  git \
  python3-pip \
  python3-venv \
  libldap2-dev \
  libpq-dev \
  libsasl2-dev \
  wget \
  curl \
  ufw

# wkhtmltopdf
WKDL="https://github.com/wkhtmltopdf/wkhtmltopdf/releases/download/0.12.5/wkhtmltox_0.12.5-1.bionic_amd64.deb"
if ! command -v wkhtmltopdf >/dev/null; then
  wget $WKDL -O /tmp/wkhtmltox.deb
  dpkg -i /tmp/wkhtmltox.deb || apt-get install -f -y
fi

# libssl1.1 (best effort)
if ! dpkg -l | grep -q libssl1.1; then
  wget http://archive.ubuntu.com/ubuntu/pool/main/o/openssl/libssl1.1_1.1.0g-2ubuntu4_amd64.deb -O /tmp/libssl1.1.deb
  dpkg -i /tmp/libssl1.1.deb || true
fi

# firewall
ufw allow OpenSSH
ufw allow 80
ufw allow 443
ufw --force enable

echo "✅ Base dependencies ready"
