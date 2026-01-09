#!/bin/bash
set -e

echo "=== ODOO 18 INSTALL SCRIPT + BACKUP + CLOUDFLARE ==="

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
apt update && apt upgrade -y

# =========================
# DEPENDENCIES
# =========================
apt install -y \
 git python3-pip python3-venv python3-dev \
 libldap2-dev libpq-dev libsasl2-dev \
 postgresql-client ufw curl tar

# =========================
# ODOO USER
# =========================
id $ODOO_USER &>/dev/null || useradd -m -d $ODOO_HOME -U -r -s /bin/bash $ODOO_USER

# =========================
# CLONE ODOO
# =========================
mkdir -p $ODOO_HOME && cd $ODOO_HOME
[ ! -d odoo ] && git clone https://github.com/odoo/odoo.git --depth 1 --branch $ODOO_VERSION odoo

# =========================
# PYTHON VENV
# =========================
python3 -m venv $ODOO_HOME/venv
chown -R $ODOO_USER:$ODOO_USER $ODOO_HOME

su - $ODOO_USER <<EOF
source $ODOO_HOME/venv/bin/activate
pip install --upgrade pip
pip install -r $ODOO_HOME/odoo/requirements.txt
EOF

# =========================
# CONFIG
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
# BACKUP SCRIPT
# =========================
mkdir -p $BACKUP_DIR

cat > /usr/local/bin/backup_odoo.sh <<'EOF'
#!/bin/bash
DATE=$(date +%F)
ODOO_HOME="/opt/odoo18"
BACKUP_DIR="/backup/odoo"

tar -czf $BACKUP_DIR/filestore_$DATE.tar.gz /opt/odoo18/.local/share/Odoo
tar -czf $BACKUP_DIR/config_$DATE.tar.gz /opt/odoo18/odoo.conf

find $BACKUP_DIR -type f -mtime +14 -delete
EOF

chmod +x /usr/local/bin/backup_odoo.sh

# =========================
# CRON
# =========================
(crontab -l 2>/dev/null; echo "0 2 * * * /usr/local/bin/backup_odoo.sh") | crontab -

# =========================
# CLOUDFLARE TUNNEL
# =========================
curl -fsSL https://pkg.cloudflare.com/install.sh | bash
apt install -y cloudflared

echo "Login Cloudflare:"
echo "cloudflared tunnel login"

# =========================
# FIREWALL
# =========================
ufw allow ssh
ufw allow 80
ufw allow 443
ufw --force enable

echo "=== ODOO READY ==="
