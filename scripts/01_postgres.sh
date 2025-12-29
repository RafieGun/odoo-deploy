#!/bin/bash
set -e

echo "🐘 [01] PostgreSQL setup"

apt install -y postgresql postgresql-contrib

systemctl enable postgresql
systemctl start postgresql

# create odoo db user (socket auth)
sudo -u postgres psql <<EOF
DO \$\$
BEGIN
  IF NOT EXISTS (
    SELECT FROM pg_roles WHERE rolname = '${ODOO_USER}'
  ) THEN
    CREATE ROLE ${ODOO_USER} WITH LOGIN CREATEDB;
  END IF;
END
\$\$;
EOF

echo "✅ PostgreSQL ready (user: ${ODOO_USER})"
