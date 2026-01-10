#!/bin/bash
set -e

echo "=== POSTGRESQL PRODUCTION SERVER (LOCKED) ==="

# =========================
# VARIABLE (WAJIB GANTI)
# =========================
PG_VERSION="16"

DB_IP="100.100.64.57"          # IP VM DATABASE (TAILSCALE / NIC)
ODOO_TAILSCALE_IP="100.74.142.51"

ODOO_DB_USER="odoo18"
ODOO_DB_PASS="GANTI_PASSWORD_DB"

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
# ENABLE POSTGRES
# =========================
systemctl enable postgresql
systemctl start postgresql

# =========================
# CONFIG FILE
# =========================
PG_CONF="/etc/postgresql/${PG_VERSION}/main/postgresql.conf"
PG_HBA="/etc/postgresql/${PG_VERSION}/main/pg_hba.conf"

# =========================
# LOCK LISTEN ADDRESS (ONLY DB IP)
# =========================
sed -i "s/^#\\?listen_addresses.*/listen_addresses = '${DB_IP}'/" $PG_CONF
sed -i "s/^#\\?port.*/port = ${PG_PORT}/" $PG_CONF

# =========================
# pg_hba.conf (AUTO INSERT TOP)
# =========================
# allow local (pgAdmin / local psql)
sed -i "1ilocal   all     all                     md5" $PG_HBA

# allow Odoo VM via tailscale
sed -i "2ihost    all     all     ${ODOO_TAILSCALE_IP}/32    md5" $PG_HBA

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
    CREATE ROLE ${ODOO_DB_USER}
    LOGIN PASSWORD '${ODOO_DB_PASS}'
    CREATEDB;
  END IF;
END
\$\$;
EOF

# =========================
# BACKUP SCRIPT (VM DB)
# =========================
mkdir -p $BACKUP_DIR

cat > /usr/local/bin/backup_postgres.sh <<'EOF'
#!/bin/bash
set -e

DATE=$(date +%F)
BACKUP_DIR="/backup/postgres"

pg_isready -q || exit 1

sudo -u postgres pg_dumpall | gzip > $BACKUP_DIR/all_db_$DATE.sql.gz

find $BACKUP_DIR -type f -mtime +14 -delete
EOF

chmod +x /usr/local/bin/backup_postgres.sh

# =========================
# CRON (ANTI DUPLIKAT)
# =========================
crontab -l 2>/dev/null | grep -v backup_postgres.sh | crontab -
(crontab -l 2>/dev/null; echo "0 2 * * * /usr/local/bin/backup_postgres.sh") | crontab -

# =========================
# FIREWALL (STRICT)
# =========================
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow from ${ODOO_TAILSCALE_IP} to any port ${PG_PORT}
ufw allow ssh
ufw --force enable

echo "=== POSTGRES PRODUCTION READY (LOCKED) ==="
