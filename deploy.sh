#!/usr/bin/env bash
set -euo pipefail

source .env

case "$ROLE" in
  db)
    bash scripts/base.sh
    bash scripts/postgres.sh
    ;;
  odoo)
    bash scripts/base.sh
    bash scripts/odoo.sh
    bash scripts/nginx.sh
    ;;
  *)
    echo "❌ ROLE must be 'db' or 'odoo'"
    exit 1
    ;;
esac
