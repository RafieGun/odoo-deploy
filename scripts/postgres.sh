#!/usr/bin/env bash
set -euo pipefail

log() { echo "[POSTGRES] $*"; }
die() { echo "[POSTGRES][ERROR] $*" >&2; exit 1; }

require_root() {
  [[ "$EUID" -eq 0 ]] || die "Run as root"
}

require_env() {
  : "${PG_VERSION:?PG_VERSION not set}"
  : "${PG_DB:?PG_DB not set}"
  : "${PG_USER:?PG_USER not set}"
  : "${PG_PASSWORD:?PG_PASSWORD not set}"
  : "${PG_LISTEN_ADDRESS:?PG_LISTEN_ADDRESS not set}"
  : "${PG_ALLOWED_NET:?PG_ALLOWED_NET not set}"
}

install_postgres() {
  log "Installing PostgreSQL ${PG_VERSION}"
  apt-get install -y postgresql postgresql-contrib
}

configure_postgres() {
  local conf="/etc/postgresql/${PG_VERSION}/main/postgresql.conf"
  local hba="/etc/postgresql/${PG_VERSION}/main/pg_hba.conf"

  log "Configuring postgresql.conf"
  sed -i "s/^#listen_addresses.*/listen_addresses = '${PG_LISTEN_ADDRESS}'/" "$conf"

  log "Configuring pg_hba.conf"
  grep -q "${PG_ALLOWED_NET}" "$hba" || echo \
"host    all     all     ${PG_ALLOWED_NET}    md5" >> "$hba"

  systemctl restart postgresql
}

create_user_and_db() {
  log "Creating role & database"

  su - postgres -c "psql <<EOF
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${PG_USER}') THEN
    CREATE ROLE ${PG_USER} LOGIN PASSWORD '${PG_PASSWORD}' CREATEDB;
  END IF;
END
\$\$;

CREATE DATABASE ${PG_DB} OWNER ${PG_USER};
EOF" || true
}

open_firewall() {
  log "Opening firewall 5432"
  ufw allow 5432/tcp || true
}

main() {
  require_root
  require_env
  install_postgres
  configure_postgres
  create_user_and_db
  open_firewall
  log "PostgreSQL ready 🎉"
}

main "$@"
