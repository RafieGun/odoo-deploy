#!/bin/bash
set -e

echo "=== POSTGRESQL PRODUCTION SERVER ==="

# =========================
# VARIABLE (WAJIB GANTI)
# =========================
PG_VERSION="16"
ODOO_DB_USER="odoo18"
ODOO_DB_PASS="GANTI_PASSWORD_DB"
ODOO_TAILSCALE_IP="100.x.x.x"

PG_PORT="5432"
BACKUP_DIR="/backup/postgres"

# =========================
# ROOT CHECK
# =========================
[ "$EUID" -ne 0 ] && echo "Run as root!" && exit 1

# =========================
# INSTALL
# =========================
apt update -y
apt install -y postgresql postgresql-client ufw gzip

# =========================
# ENABLE POSTGRES (AUTO BOOT)
# =========================
systemctl enable postgresql
systemctl enable postgresql@${PG_VERSION}-main
systemctl start postgresql

# =========================
# CONFIG
# =========================
PG_CONF="/etc/postgresql/${PG_VERSION}/main/postgresql.conf"
PG_HBA="/etc/postgresql/${PG_VERSION}/main/pg_hba.conf"

sed -i "s/#listen_addresses =.*/listen_addresses='*'/" $PG_CONF
sed -i "s/#port =.*/port = ${PG_PORT}/" $PG_CONF

grep -q "$ODOO_TAILSCALE_IP" $PG_HBA || \
echo "host all all ${ODOO_TAILSCALE_IP}/32 md5" >> $PG_HBA

systemctl restart postgresql

# =========================
# DB USER (IDEMPOTENT)
# =========================
sudo -u postgres psql <<EOF
DO \$\$
BEGIN
  IF NOT EXISTS (
    SELECT FROM pg_roles WHERE rolname = '${ODOO_DB_USER}'
  ) THEN
    CREATE ROLE ${ODOO_DB_USER} LOGIN PASSWORD '${ODOO_DB_PASS}' CREATEDB;
  END IF;
END
\$\$;
EOF

# =========================
# SYSTEMD HARDENING
# =========================
mkdir -p /etc/systemd/system/postgresql.service.d

cat > /etc/systemd/system/postgresql.service.d/restart.conf <<EOF
[Service]
Restart=always
RestartSec=5
EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl restart postgresql

# =========================
# BACKUP SCRIPT
# =========================
mkdir -p $BACKUP_DIR

cat > /usr/local/bin/backup_postgres.sh <<EOF
#!/bin/bash

DATE=\$(date +%F)
BACKUP_DIR="/backup/postgres"

pg_isready -q || exit 1

sudo -u postgres pg_dumpall | gzip > \$BACKUP_DIR/all_db_\$DATE.sql.gz

find \$BACKUP_DIR -type f -mtime +14 -delete
EOF

chmod +x /usr/local/bin/backup_postgres.sh

# =========================
# CRON (ANTI DUPLIKAT)
# =========================
crontab -l 2>/dev/null | grep -v backup_postgres.sh | crontab -
(crontab -l 2>/dev/null; echo "0 2 * * * /usr/local/bin/backup_postgres.sh") | crontab -

# =========================
# FIREWALL (ZERO TRUST)
# =========================
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow from ${ODOO_TAILSCALE_IP} to any port ${PG_PORT}
ufw allow ssh
ufw --force enable

echo "=== POSTGRES PRODUCTION READY ==="
