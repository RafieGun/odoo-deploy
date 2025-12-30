#!/bin/bash
set -e

echo "🌐 [03] Nginx setup for Odoo + pgAdmin"

if [ "$EUID" -ne 0 ]; then
  echo "❌ Run as root"
  exit 1
fi

ODOO_PORT=${ODOO_PORT:-8069}
PGADMIN_PORT=8080

# ===== STOP APACHE =====
# if systemctl list-unit-files | grep -q apache2; then
#   echo "🛑 Disabling Apache2"
#   systemctl stop apache2 || true
#   systemctl disable apache2 || true
#   systemctl mask apache2 || true
# fi

# ===== INSTALL NGINX =====
apt update
apt install -y nginx
systemctl enable nginx

rm -f /etc/nginx/sites-enabled/default

# ===== NGINX CONFIG =====
cat >/etc/nginx/sites-available/odoo-local <<EOF
server {
    listen 80 default_server;
    server_name _;

    proxy_read_timeout 720s;
    proxy_connect_timeout 720s;
    proxy_send_timeout 720s;

    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Real-IP \$remote_addr;

    # ===== ODOO =====
    location / {
        proxy_pass http://127.0.0.1:${ODOO_PORT};
    }

    # ===== PGADMIN =====
    location /pgadmin/ {
        proxy_pass http://127.0.0.1:${PGADMIN_PORT}/;
        proxy_set_header Host \$host;
        proxy_set_header X-Script-Name /pgadmin;
    }
}
EOF

ln -sf /etc/nginx/sites-available/odoo-local /etc/nginx/sites-enabled/odoo-local

nginx -t
systemctl restart nginx

echo "✅ Nginx running"
echo "👉 Odoo    : http://SERVER_IP"
echo "👉 pgAdmin : http://SERVER_IP/pgadmin"
