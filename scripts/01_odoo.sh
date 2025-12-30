#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { echo "[02] $*"; }
die() { echo "[02] ERROR: $*" >&2; exit 1; }

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "Run as root."
}

load_env() {
  if [[ -f "${SCRIPT_DIR}/.env" ]]; then
    # shellcheck disable=SC1091
    set -a; source "${SCRIPT_DIR}/.env"; set +a
    log "Loaded .env"
  fi
}

require_vars() {
  local missing=0
  for v in "$@"; do
    if [[ -z "${!v:-}" ]]; then
      echo "[02] Missing env var: $v" >&2
      missing=1
    fi
  done
  [[ "$missing" -eq 0 ]] || exit 1
}

ensure_apt() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y --no-install-recommends \
    postgresql postgresql-client postgresql-contrib \
    git \
    python3 python3-venv python3-pip \
    libpq-dev
}

ensure_postgres_running() {
  systemctl enable postgresql >/dev/null
  systemctl start postgresql
}

psql_as_postgres() {
  su - postgres -c "psql -v ON_ERROR_STOP=1 $*"
}

ensure_db_role() {
  local db_user="$1"
  local db_pass="$2"

  # Escape single quotes for SQL literal usage
  local pass_esc="${db_pass//\'/\'\'}"

  log "Ensuring Postgres role: ${db_user} (LOGIN + CREATEDB; not SUPERUSER)"
  psql_as_postgres <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${db_user}') THEN
    CREATE ROLE ${db_user} LOGIN CREATEDB PASSWORD '${pass_esc}';
  ELSE
    ALTER ROLE ${db_user} WITH LOGIN CREATEDB PASSWORD '${pass_esc}';
  END IF;
END
\$\$;
SQL
}

ensure_system_user() {
  local odoo_user="$1"
  local odoo_home="$2"

  if id "$odoo_user" &>/dev/null; then
    log "System user exists: $odoo_user"
    return 0
  fi

  log "Creating system user: $odoo_user"
  adduser --system --home "$odoo_home" --group --shell /bin/bash "$odoo_user"
}

run_as_odoo() {
  local odoo_user="$1"
  shift
  su - "$odoo_user" -c "$*"
}

ensure_odoo_source() {
  local odoo_user="$1"
  local odoo_dir="$2"
  local odoo_version="$3"

  if [[ -d "$odoo_dir/.git" ]]; then
    log "Odoo source already present: $odoo_dir"
    return 0
  fi

  log "Cloning Odoo ${odoo_version} into ${odoo_dir}"
  install -d -m 0755 -o "$odoo_user" -g "$odoo_user" "$(dirname "$odoo_dir")"

  run_as_odoo "$odoo_user" "git clone https://github.com/odoo/odoo.git --depth 1 --branch '${odoo_version}' --single-branch '${odoo_dir}'"
}

ensure_venv_and_requirements() {
  local odoo_user="$1"
  local venv_dir="$2"
  local odoo_dir="$3"

  if [[ ! -d "$venv_dir" ]]; then
    log "Creating venv: $venv_dir"
    run_as_odoo "$odoo_user" "python3 -m venv '${venv_dir}'"
  else
    log "Venv exists: $venv_dir"
  fi

  log "Installing Python requirements"
  run_as_odoo "$odoo_user" "
    set -e;
    source '${venv_dir}/bin/activate';
    pip install --upgrade pip setuptools wheel;
    pip install -r '${odoo_dir}/requirements.txt';
  "
}

ensure_dirs() {
  local odoo_user="$1"
  local odoo_group="$2"
  local data_dir="$3"
  local log_dir="$4"
  local custom_addons="$5"

  install -d -m 0750 -o "$odoo_user" -g "$odoo_group" "$data_dir"
  install -d -m 0750 -o "$odoo_user" -g "$odoo_group" "$log_dir"
  install -d -m 0755 -o "$odoo_user" -g "$odoo_group" "$custom_addons"
  install -d -m 0755 /etc/odoo
}

write_odoo_conf() {
  local conf_path="$1"
  local master_pass="$2"
  local db_user="$3"
  local db_pass="$4"
  local addons_path="$5"
  local data_dir="$6"
  local logfile="$7"
  local port="$8"
  local proxy_mode="$9"
  local list_db="${10}"

  local wkhtml=""
  if command -v wkhtmltopdf >/dev/null 2>&1; then
    wkhtml="$(command -v wkhtmltopdf)"
  fi

  log "Writing config: $conf_path"
  umask 027
  cat > "$conf_path" <<EOF
[options]
; Master password (Database Manager)
admin_passwd = ${master_pass}

; Database
db_host = False
db_port = 5432
db_user = ${db_user}
db_password = ${db_pass}

; Server
xmlrpc_port = ${port}
proxy_mode = ${proxy_mode}
list_db = ${list_db}

; Paths
addons_path = ${addons_path}
data_dir = ${data_dir}

; Logging
logfile = ${logfile}

; wkhtmltopdf (PDF reports)
wkhtmltopdf = ${wkhtml}
EOF
  chmod 0640 "$conf_path"
}

write_systemd_service() {
  local service_name="$1"
  local odoo_user="$2"
  local odoo_group="$3"
  local venv_dir="$4"
  local odoo_dir="$5"
  local conf_path="$6"

  local unit="/etc/systemd/system/${service_name}.service"

  log "Writing systemd unit: ${unit}"
  cat > "$unit" <<EOF
[Unit]
Description=Odoo (${service_name})
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=${odoo_user}
Group=${odoo_group}
WorkingDirectory=${odoo_dir}
ExecStart=${venv_dir}/bin/python3 ${odoo_dir}/odoo-bin -c ${conf_path}
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable "${service_name}" >/dev/null
}

write_logrotate() {
  local logfile="$1"
  local service_name="$2"
  local lr="/etc/logrotate.d/${service_name}"

  log "Writing logrotate: ${lr}"
  cat > "$lr" <<EOF
${logfile} {
  daily
  rotate 14
  compress
  delaycompress
  missingok
  notifempty
  copytruncate
}
EOF
}

main() {
  require_root
  load_env

  require_vars ODOO_USER ODOO_VERSION ODOO_MASTER_PASS DB_USER DB_PASS

  local ODOO_USER_="${ODOO_USER}"
  local ODOO_VERSION_="${ODOO_VERSION}"
  local ODOO_PORT_="${ODOO_PORT:-8069}"
  local PROXY_MODE_="${PROXY_MODE:-False}"
  local LIST_DB_="${LIST_DB:-False}"

  local ODOO_HOME="/opt/${ODOO_USER_}"
  local ODOO_DIR="${ODOO_HOME}/odoo"
  local VENV_DIR="${ODOO_HOME}/venv"
  local CUSTOM_ADDONS="${ODOO_HOME}/custom-addons"

  local DATA_DIR="/var/lib/odoo/${ODOO_USER_}"
  local LOG_DIR="/var/log/odoo"
  local LOG_FILE="${LOG_DIR}/${ODOO_USER_}.log"

  local CONF_PATH="/etc/odoo/${ODOO_USER_}.conf"
  local SERVICE_NAME="${ODOO_USER_}"

  ensure_apt
  ensure_postgres_running
  ensure_db_role "${DB_USER}" "${DB_PASS}"

  ensure_system_user "${ODOO_USER_}" "${ODOO_HOME}"
  ensure_odoo_source "${ODOO_USER_}" "${ODOO_DIR}" "${ODOO_VERSION_}"
  ensure_venv_and_requirements "${ODOO_USER_}" "${VENV_DIR}" "${ODOO_DIR}"

  ensure_dirs "${ODOO_USER_}" "${ODOO_USER_}" "${DATA_DIR}" "${LOG_DIR}" "${CUSTOM_ADDONS}"

  # Ensure ownership for Odoo home
  chown -R "${ODOO_USER_}:${ODOO_USER_}" "${ODOO_HOME}"

  # addons_path: core addons + custom addons
  local ADDONS_PATH="${ODOO_DIR}/addons,${CUSTOM_ADDONS}"

  write_odoo_conf "${CONF_PATH}" "${ODOO_MASTER_PASS}" "${DB_USER}" "${DB_PASS}" \
    "${ADDONS_PATH}" "${DATA_DIR}" "${LOG_FILE}" "${ODOO_PORT_}" "${PROXY_MODE_}" "${LIST_DB_}"

  chown root:"${ODOO_USER_}" "${CONF_PATH}"

  write_systemd_service "${SERVICE_NAME}" "${ODOO_USER_}" "${ODOO_USER_}" "${VENV_DIR}" "${ODOO_DIR}" "${CONF_PATH}"
  write_logrotate "${LOG_FILE}" "${SERVICE_NAME}"

  log "Starting service: ${SERVICE_NAME}"
  systemctl restart "${SERVICE_NAME}"

  if systemctl is-active --quiet "${SERVICE_NAME}"; then
    log "Odoo is running"
    log "Config : ${CONF_PATH}"
    log "Log    : ${LOG_FILE}"
    log "Port   : ${ODOO_PORT_}"
  else
    log "Odoo failed to start. Check:"
    log "  journalctl -u ${SERVICE_NAME} -n 200 --no-pager"
    log "  tail -n 200 ${LOG_FILE}"
    exit 1
  fi
}

main "$@"