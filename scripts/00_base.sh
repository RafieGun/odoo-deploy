#!/bin/bash
set -e

echo "💻 Installing dependencies..."
apt update && apt upgrade -y
apt install -y git python3-pip python3-venv \
    libldap2-dev libpq-dev libsasl2-dev wget curl ufw

# wkhtmltopdf
WKDL="https://github.com/wkhtmltopdf/wkhtmltopdf/releases/download/0.12.5/wkhtmltox_0.12.5-1.bionic_amd64.deb"
wget $WKDL -O /tmp/wkhtmltox.deb
dpkg -i /tmp/wkhtmltox.deb || apt-get install -f -y

# libssl1.1
wget http://archive.ubuntu.com/ubuntu/pool/main/o/openssl/libssl1.1_1.1.0g-2ubuntu4_amd64.deb -O /tmp/libssl1.1.deb
dpkg -i /tmp/libssl1.1.deb || apt-get install -f -y
