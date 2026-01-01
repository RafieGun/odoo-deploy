#!/bin/bash
set -e

echo "=== ODOO 18 INSTALL SCRIPT ==="

# =========================
# VARIABLE
# =========================
ODOO_USER="odoo18"
ODOO_HOME="/opt/odoo18"
ODOO_VERSION="18.0"
DB_PASSWORD="admin"
ADMIN_PASSWORD="Indramil@123"

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
  postgresql \
  postgresql-client

# =========================
# POSTGRES USER
# =========================
sudo -u postgres psql <<EOF
DO \$\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${ODOO_USER}') THEN
      CREATE ROLE ${ODOO_USER} WITH LOGIN SUPERUSER PASSWORD '${DB_PASSWORD}';
   END IF;
END
\$\$;
EOF

# =========================
# ODOO SYSTEM USER
# =========================
if ! id "$ODOO_USER" &>/dev/null; then
  useradd -m -d $ODOO_HOME -U -r -s /bin/bash $ODOO_USER
fi

# =========================
# CLONE ODOO
# =========================
mkdir -p $ODOO_HOME
cd $ODOO_HOME

if [ ! -d "odoo" ]; then
  git clone https://github.com/odoo/odoo.git \
    --depth 1 \
    --branch $ODOO_VERSION \
    --single-branch odoo
fi

# =========================
# PYTHON VENV
# =========================
python3 -m venv $ODOO_HOME/venv

# =========================
# PERMISSION
# =========================
chown -R $ODOO_USER:$ODOO_USER $ODOO_HOME

# =========================
# INSTALL PYTHON REQS
# =========================
su - $ODOO_USER <<EOF
source $ODOO_HOME/venv/bin/activate
pip install --upgrade pip
pip install -r $ODOO_HOME/odoo/requirements.txt
EOF

# =========================
# ODOO CONFIG
# =========================
mkdir -p $ODOO_HOME/odoo/custom

cat > $ODOO_HOME/odoo/debian/odoo.conf <<EOF
[options]
admin_passwd = ${ADMIN_PASSWORD}
db_host = False
db_port = 5432
db_user = ${ODOO_USER}
db_password = ${DB_PASSWORD}
addons_path = ${ODOO_HOME}/odoo/addons,${ODOO_HOME}/odoo/custom
default_productivity_apps = True
wkhtmltopdf = /usr/local/bin
pg_path = /usr/bin
logfile = ${ODOO_HOME}/odoo.log
EOF

chown $ODOO_USER:$ODOO_USER $ODOO_HOME/odoo/debian/odoo.conf

echo "=== INSTALL DONE ==="
