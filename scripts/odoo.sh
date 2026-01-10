#!/bin/bash
set -e

echo "=== ODOO 18 INSTALL SCRIPT (FINAL + WKHTMLTOPDF + BACKUP) ==="

# =========================
# VARIABLE (GANTI SESUAI LU)
# =========================
ODOO_USER="odoo18"
ODOO_HOME="/opt/odoo18"
ODOO_VERSION="18.0"

DB_HOST="100.x.x.x"        # IP TAILSCALE VM DB
DB_PASSWORD="admin"
ADMIN_PASSWORD="apaya"

BACKUP_DIR="/backup/odoo"

# =========================
# ROOT CHECK
# =========================
if [ "$EUID" -ne 0 ]; then
  echo "Run as root!"
  exit 1
fi

# =========================
# SYSTEM UPDATE
# =========================
apt update -y

# =========================
# DEPENDENCIES
# =========================
apt install -y \
  git \
  python3-pip \
  python3-venv \
  python3-dev \
  libldap2-dev \
  libpq-dev \
  libsasl2-dev \
  postgresql-client \
  tar \
  ufw \
  wget

# =========================
# WKHTMLTOPDF 0.12.5 (QT PATCHED)
# =========================
echo "=== INSTALL WKHTMLTOPDF 0.12.5 (QT PATCHED) ==="

if command -v wkhtmltopdf >/dev/null 2>&1; then
  echo "wkhtmltopdf already installed:"
  wkhtmltopdf --version
else
  echo "Installing wkhtmltopdf 0.12.5 (QT patched)"

  apt install -y \
    fontconfig \
    libfreetype6 \
    libjpeg-turbo8 \
    libpng16-16 \
    libxrender1 \
    libxext6 \
    xfonts-base \
    xfonts-75dpi

  # libssl1.1 (legacy, wajib utk wkhtmltopdf)
  if ! dpkg -l | grep -q libssl1.1; then
    cd /tmp
    wget http://archive.ubuntu.com/ubuntu/pool/main/o/openssl/libssl1.1_1.1.0g-2ubuntu4_amd64.deb
    dpkg -i libssl1.1_1.1.0g-2ubuntu4_amd64.deb
  fi

  cd /tmp
  wget https://github.com/wkhtmltopdf/wkhtmltopdf/releases/download/0.12.5/wkhtmltox_0.12.5-1.bionic_amd64.deb
  dpkg -i wkhtmltox_0.12.5-1.bionic_amd64.deb
fi

wkhtmltopdf --version

# =========================
# ODOO SYSTEM USER
# =========================
if ! id "$ODOO_USER" &>/dev/null; then
  useradd -m -d "$ODOO_HOME" -U -r -s /bin/bash "$ODOO_USER"
fi

# =========================
# CLONE ODOO
# =========================
mkdir -p "$ODOO_HOME"
cd "$ODOO_HOME"

if [ ! -d "odoo" ]; then
  git clone https://github.com/odoo/odoo.git \
    --depth 1 \
    --branch "$ODOO_VERSION" \
    --single-branch odoo
fi

# =========================
# PYTHON VENV
# =========================
if [ ! -d "$ODOO_HOME/venv" ]; then
  python3 -m venv "$ODOO_HOME/venv"
fi

chown -R "$ODOO_USER:$ODOO_USER" "$ODOO_HOME"

# =========================
# INSTALL PYTHON REQS
# =========================
su - "$ODOO_USER" <<EOF
source "$ODOO_HOME/venv/bin/activate"
pip install --upgrade pip
pip install -r "$ODOO_HOME/odoo/requirements.txt"
EOF

# =========================
# ODOO CONFIG
# =========================
mkdir -p "$ODOO_HOME/odoo/muk"
mkdir -p "$ODOO_HOME/odoo/debian"

cat > "$ODOO_HOME/odoo/debian/odoo.conf" <<EOF
[options]
admin_passwd = ${ADMIN_PASSWORD}

db_host = ${DB_HOST}
db_port = 5432
db_user = ${ODOO_USER}
db_password = ${DB_PASSWORD}

proxy_mode = True
dbfilter = ^%d\$
list_db = False

addons_path = ${ODOO_HOME}/odoo/addons, ${ODOO_HOME}/odoo/muk
logfile = ${ODOO_HOME}/odoo.log

wkhtmltopdf = /usr/local/bin
EOF

chown "$ODOO_USER:$ODOO_USER" "$ODOO_HOME/odoo/debian/odoo.conf"
chmod 640 "$ODOO_HOME/odoo/debian/odoo.conf"

# =========================
# SYSTEMD SERVICE
# =========================
cat > /etc/systemd/system/odoo18.service <<EOF
[Unit]
Description=Odoo 18
After=network.target

[Service]
Type=simple
User=${ODOO_USER}
ExecStart=${ODOO_HOME}/venv/bin/python3 ${ODOO_HOME}/odoo/odoo-bin -c ${ODOO_HOME}/odoo/debian/odoo.conf
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable odoo18
systemctl restart odoo18

# =========================
# BACKUP SCRIPT
# =========================
mkdir -p "$BACKUP_DIR"

cat > /usr/local/bin/backup_odoo.sh <<'EOF'
#!/bin/bash

DATE=$(date +%F)
BACKUP_DIR="/backup/odoo"
ODOO_HOME="/opt/odoo18"

# backup filestore
tar -czf $BACKUP_DIR/filestore_$DATE.tar.gz \
  $ODOO_HOME/.local/share/Odoo

# backup config
tar -czf $BACKUP_DIR/config_$DATE.tar.gz \
  $ODOO_HOME/odoo/debian/odoo.conf

# cleanup >14 hari
find $BACKUP_DIR -type f -mtime +14 -delete
EOF

chmod +x /usr/local/bin/backup_odoo.sh

# =========================
# CRON BACKUP (ANTI DUPLIKAT)
# =========================
crontab -l 2>/dev/null | grep -v backup_odoo.sh | crontab -
(crontab -l 2>/dev/null; echo "0 2 * * * /usr/local/bin/backup_odoo.sh") | crontab -

echo "=== INSTALL DONE (ODOO + WKHTMLTOPDF + BACKUP ENABLED) ==="
