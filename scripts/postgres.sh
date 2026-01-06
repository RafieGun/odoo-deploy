#!/bin/bash
set -e

echo "=== POSTGRESQL DB SERVER FOR ODOO ==="

# =========================
# VARIABLE
# =========================
PG_VERSION="16"          # auto di Ubuntu 24.04
ODOO_DB_USER="odoo18"
ODOO_DB_PASS="apaya"
ODOO_VM_IP="192.168.1.50"   # <-- GANTI IP VM ODOO
PG_PORT="5432"

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
apt update && apt upgrade -y

# =========================
# INSTALL POSTGRESQL
# =========================
apt install -y postgresql postgresql-contrib postgresql-client ufw

# =========================
# POSTGRES CONFIG (LISTEN ALL)
# =========================
PG_CONF="/etc/postgresql/${PG_VERSION}/main/postgresql.conf"
PG_HBA="/etc/postgresql/${PG_VERSION}/main/pg_hba.conf"

sed -i "s/^#listen_addresses.*/listen_addresses = '*'/" $PG_CONF
sed -i "s/^#port.*/port = ${PG_PORT}/" $PG_CONF

# =========================
# PG_HBA ACCESS RULE
# =========================
if ! grep -q "$ODOO_VM_IP" $PG_HBA; then
  echo "host    all     all     ${ODOO_VM_IP}/32    md5" >> $PG_HBA
fi

# =========================
# RESTART POSTGRES
# =========================
systemctl restart postgresql

# =========================
# CREATE ODOO DB USER
# =========================
sudo -u postgres psql <<EOF
DO \$\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${ODOO_DB_USER}') THEN
      CREATE ROLE ${ODOO_DB_USER} WITH LOGIN PASSWORD '${ODOO_DB_PASS}';
      ALTER ROLE ${ODOO_DB_USER} CREATEDB;
   END IF;
END
\$\$;
EOF

# =========================
# FIREWALL (STRICT)
# =========================
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow from ${ODOO_VM_IP} to any port ${PG_PORT}
ufw allow ssh
ufw allow https
ufw allow http
ufw --force enable

# =========================
# FINAL CHECK
# =========================
echo "=== FINAL CHECK ==="
ss -lntp | grep ${PG_PORT} || true
ufw status verbose

echo "=== DB SERVER READY ==="
echo "Allowed Odoo VM IP : ${ODOO_VM_IP}"
echo "PostgreSQL Port    : ${PG_PORT}"
