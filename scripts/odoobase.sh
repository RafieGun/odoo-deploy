#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log(){ echo "[ODOO-BASE] $*"; }
die(){ echo "[ODOO-BASE] ERROR: $*" >&2; exit 1; }
require_root(){ [[ "${EUID}" -eq 0 ]] || die "Run as root."; }

load_env() {
  if [[ -f "${SCRIPT_DIR}/.env" ]]; then
    # shellcheck disable=SC1091
    set -a; source "${SCRIPT_DIR}/.env"; set +a
    log "Loaded .env"
  fi
}

os_codename() {
  # shellcheck disable=SC1091
  source /etc/os-release
  echo "${VERSION_CODENAME:-}"
}

install_packages() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get upgrade -y

  apt-get install -y --no-install-recommends \
    ca-certificates gnupg \
    git curl wget \
    python3 python3-pip python3-venv python3-dev \
    build-essential \
    libpq-dev libldap2-dev libsasl2-dev \
    libxml2-dev libxslt1-dev \
    libjpeg-dev zlib1g-dev \
    libffi-dev libssl-dev \
    fontconfig xfonts-75dpi xfonts-base \
    ufw

  # optional, best effort
  apt-get install -y --no-install-recommends nodejs npm || true
}

install_wkhtmltopdf() {
  if command -v wkhtmltopdf >/dev/null 2>&1; then
    log "wkhtmltopdf already installed: $(wkhtmltopdf --version || true)"
    return 0
  fi

  if [[ -n "${WKHTMLTOPDF_URL:-}" ]]; then
    log "Installing wkhtmltopdf from WKHTMLTOPDF_URL"
    wget -q "${WKHTMLTOPDF_URL}" -O /tmp/wkhtmltox.deb
    dpkg -i /tmp/wkhtmltox.deb || apt-get install -f -y
    command -v wkhtmltopdf >/dev/null 2>&1 || die "wkhtmltopdf install failed (WKHTMLTOPDF_URL)."
    return 0
  fi

  local codename; codename="$(os_codename)"
  case "$codename" in
    bionic)
      wget -q "https://github.com/wkhtmltopdf/wkhtmltopdf/releases/download/0.12.5/wkhtmltox_0.12.5-1.bionic_amd64.deb" -O /tmp/wkhtmltox.deb
      dpkg -i /tmp/wkhtmltox.deb || apt-get install -f -y
      ;;
    focal)
      wget -q "https://github.com/wkhtmltopdf/wkhtmltopdf/releases/download/0.12.6/wkhtmltox_0.12.6-1.focal_amd64.deb" -O /tmp/wkhtmltox.deb
      dpkg -i /tmp/wkhtmltox.deb || apt-get install -f -y
      ;;
    *)
      # Avoid libssl1.1 injection: try distro package
      apt-get install -y wkhtmltopdf || true
      ;;
  esac

  command -v wkhtmltopdf >/dev/null 2>&1 || die "wkhtmltopdf not installed. Set WKHTMLTOPDF_URL in .env to force a known-good .deb."
  log "wkhtmltopdf installed: $(wkhtmltopdf --version || true)"
}

setup_ufw() {
  local enable="${ENABLE_UFW:-1}"
  [[ "$enable" == "1" ]] || { log "UFW skipped"; return 0; }

  local ssh_port="${SSH_PORT:-22}"
  ufw allow "${ssh_port}/tcp" >/dev/null || true

  [[ "${ALLOW_HTTP:-1}" == "1" ]] && ufw allow 80/tcp >/dev/null || true
  [[ "${ALLOW_HTTPS:-1}" == "1" ]] && ufw allow 443/tcp >/dev/null || true
  [[ "${ALLOW_ODOO_PORT:-0}" == "1" ]] && ufw allow 8069/tcp >/dev/null || true

  ufw --force enable >/dev/null || true
  ufw status verbose || true
}

main() {
  require_root
  load_env
  install_packages
  install_wkhtmltopdf
  setup_ufw
  log "Done."
}

main "$@"