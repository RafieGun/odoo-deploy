#!/bin/bash
set -e

echo "🐍 [02] Odoo core install"

# ===== SANITY CHECK =====
if [ -z "$ODOO_USER" ] || [ -z "$ODOO_HOME" ] || [ -z "$ODOO_VERSION" ]; then
  echo "❌ Missing env vars"
  exit 1
fi

# ===== CREATE USER =====
if ! id "$ODOO_USER" >/dev/null 2>&1; then
  useradd -m -d "$ODOO_HOME" -U -r -s /bin/bash "$ODOO_USER"
fi

# ===== FOLDERS =====
mkdir -p "$ODOO_HOME"/{odoo,custom-addons,venv,log}
chown -R "$ODOO_USER:$ODOO_USER" "$ODOO_HOME"

# ===== CLONE ODOO =====
if [ ! -d "$ODOO_HOME/odoo" ]; then
  sudo -u "$ODOO_USER" git clone \
    --depth 1 \
    --branch "$ODOO_VERSION.0" \
    https://github.com/odoo/odoo.git \
    "$ODOO_HOME/odoo"
fi

# ===== PYTHON VENV =====
if [ ! -d "$ODOO_HOME/venv/bin" ]; then
  sudo -u "$ODOO_USER" python3 -m venv "$ODOO_HOME/venv"
fi

sudo -u "$ODOO_USER" "$ODOO_HOME/venv/bin/pip" install --upgrade pip wheel
sudo -u "$ODOO_USER" "$ODOO_HOME/venv/bin/pip" install -r \
  "$ODOO_HOME/odoo/requirements.txt"

# ===== CONFIG =====
if [ ! -f /etc/odoo.conf ]; then
  envsubst < templates/odoo.conf.tpl > /etc/odoo.conf
fi

chown "$ODOO_USER:$ODOO_USER" /etc/odoo.conf
chmod 640 /etc/odoo.conf

echo "✅ Odoo core ready"
