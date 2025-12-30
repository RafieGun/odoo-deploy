#!/usr/bin/env bash
set -euo pipefail

log() { echo "[ODOO] $*"; }
die() { echo "[ODOO][ERROR] $*" >&2; exit 1; }

require_root() {
  [[ "$EUID" -eq 0 ]] || die "Run as root"
}

require_env() {
  : "${ODOO_VERSION:?}"
  : "${ODOO_USER:?}"
  : "${ODOO_HOME:?}"
  : "${ODOO_PORT:?}"

  : "${DB_HOST:?}"
  : "${DB_PORT:?}"
  : "${DB_USER:?}"
  : "${DB_PASSWORD:?}"
}

create_user() {
  log "Creating system user ${ODOO_USER}"
  id "$ODOO_USER" &>/dev/null || \
    useradd -m -d "$ODOO_HOME" -U -r -s /bin/bash "$ODOO_USER"
}

install_odoo() {
  log "Cloning Odoo ${ODOO_VERSION}"
  mkdir -p "$ODOO_HOME"
  chown "$ODOO_USER:$ODOO_USER" "$ODOO_HOME"

  su - "$ODOO_USER" -c "
    git clone https://github.com/odoo/odoo.git \
      --depth 1 \
      --branch ${ODOO_VERSION}.0 \
      ${ODOO_HOME}/odoo
  "
}

install_python_deps() {
  log "Installing Python requirements"
  pip3 install -r "${ODOO_HOME}/odoo/requirements.txt"
}

write_config() {
  log "Writing odoo.conf"

  cat >/etc/odoo.conf <<EOF
[options]
admin_passwd = admin
db_host = ${DB_HOST}
db_port = ${DB_PORT}
db_user = ${DB_USER}
db_password = ${DB_PASSWORD}

addons_path = ${ODOO_HOME}/odoo/addons
xmlrpc_port = ${ODOO_PORT}
logfile = ${ODOO_HOME}/odoo.log
EOF

  chown "$ODOO_USER:$ODOO_USER" /etc/odoo.conf
  chmod 640 /etc/odoo.conf
}

systemd_service() {
  log "Creating systemd service"

  cat >/etc/systemd/system/odoo.service <<EOF
[Unit]
Description=Odoo
After=network.target

[Service]
Type=simple
User=${ODOO_USER}
ExecStart=/usr/bin/python3 ${ODOO_HOME}/odoo/odoo-bin -c /etc/odoo.conf
Restart=always

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reexec
  systemctl daemon-reload
  systemctl enable odoo
  systemctl start odoo
}

main() {
  require_root
  require_env
  create_user
  install_odoo
  install_python_deps
  write_config
  systemd_service
  log "Odoo is running 🚀 (check ${ODOO_HOME}/odoo.log)"
}

main "$@"
