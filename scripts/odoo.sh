#!/bin/bash
set -e

echo "=== ODOO 18 PRODUCTION INSTALL ==="

# =========================
# VARIABLE (WAJIB GANTI)
# =========================
ODOO_USER="odoo18"
ODOO_HOME="/opt/odoo18"
ODOO_VERSION="18.0"

DB_PASSWORD="GANTI_PASSWORD_DB"
ADMIN_PASSWORD="GANTI_ADMIN_PASSWORD"

BACKUP_DIR="/backup/odoo"

# =========================
# ROOT CHECK
# =========================
[ "$EUID" -ne 0 ] && echo "Run as root!" && exit 1

# =========================
# SYSTEM UPDATE
# =========================
apt update -y

# =========================
# DEPENDENCIES
# =========================
apt install -y \
 git python3-pip python3-venv python3-dev \
 libldap2-dev libpq-dev libsasl2-dev \
 postgresql-client ufw curl tar

# =========================
# USER ODOO
# =========================
id $ODOO_USER &>/dev/null || useradd -m -d $ODOO_HOME -U -r -s /bin/bash $ODOO_USER

# =========================
# CLONE ODOO
# =========================
mkdir -p $ODOO_HOME
cd $ODOO_HOME

if [ ! -d "odoo" ]; then
  git clone https://github.com/odoo/odoo.git \
    --depth 1 --branch $ODOO_VERSION odoo
fi

# =========================
# PYTHON VENV
# =========================
if [ ! -d "$ODOO_HOME/venv" ]; then
  python3 -m venv $ODOO_HOME/venv
fi

chown -R $ODOO_USER:$ODOO_USER $ODOO_HOME

su - $ODOO_USER <<EOF
source $ODOO_HOME/venv/bin/activate
pip install --upgrade pip
pip install -r $ODOO_HOME/odoo/requirements.txt
EOF

# =========================
# ODOO CONFIG
# =========================
cat > $ODOO_HOME/odoo.conf <<EOF
[options]
admin_passwd = ${ADMIN_PASSWORD}
db_host = False
db_port = 5432
db_user = ${ODOO_USER}
db_password = ${DB_PASSWORD}
addons_path = ${ODOO_HOME}/odoo/addons
logfile = ${ODOO_HOME}/odoo.log
EOF

chown $ODOO_USER:$ODOO_USER $ODOO_HOME/odoo.conf

# =========================
# SYSTEMD ODOO (AUTO START)
# =========================
cat > /etc/systemd/system/odoo18.service <<EOF
[Unit]
Description=Odoo 18
After=network.target

[Service]
User=${ODOO_USER}
ExecStart=${ODOO_HOME}/venv/bin/python3 ${ODOO_HOME}/odoo/odoo-bin -c ${ODOO_HOME}/odoo.conf
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
mkdir -p $BACKUP_DIR

cat > /usr/local/bin/backup_odoo.sh <<'EOF'
#!/bin/bash

DATE=$(date +%F)
BACKUP_DIR="/backup/odoo"

systemctl is-active --quiet odoo18 || exit 1

tar -czf $BACKUP_DIR/filestore_$DATE.tar.gz /opt/odoo18/.local/share/Odoo
tar -czf $BACKUP_DIR/config_$DATE.tar.gz /opt/odoo18/odoo.conf

find $BACKUP_DIR -type f -mtime +14 -delete
EOF

chmod +x /usr/local/bin/backup_odoo.sh

# =========================
# CRON (ANTI DUPLIKAT)
# =========================
crontab -l 2>/dev/null | grep -v backup_odoo.sh | crontab -
(crontab -l 2>/dev/null; echo "0 2 * * * /usr/local/bin/backup_odoo.sh") | crontab -

# =========================
# CLOUDFLARE TUNNEL
# =========================
if ! command -v cloudflared &>/dev/null; then
  curl -fsSL https://pkg.cloudflare.com/install.sh | bash
  apt install -y cloudflared
fi

# =========================
# FIREWALL
# =========================
ufw allow ssh
ufw allow 80
ufw allow 443
ufw --force enable

echo "=== ODOO PRODUCTION READY ==="
