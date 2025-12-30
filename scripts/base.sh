#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { echo "[00] $*"; }
die() { echo "[00] ERROR: $*" >&2; exit 1; }

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

os_info() {
  [[ -f /etc/os-release ]] || die "/etc/os-release not found."
  # shellcheck disable=SC1091
  source /etc/os-release
  echo "${ID:-unknown}:${VERSION_CODENAME:-}"
}

install_packages() {
  export DEBIAN_FRONTEND=noninteractive
  log "Updating & upgrading packages"
  apt-get update -y
  apt-get upgrade -y

  log "Installing base dependencies"
  apt-get install -y --no-install-recommends \
    ca-certificates gnupg lsb-release \
    git curl wget \
    python3 python3-pip python3-venv python3-dev \
    build-essential \
    libpq-dev libldap2-dev libsasl2-dev \
    libxml2-dev libxslt1-dev \
    libjpeg-dev zlib1g-dev \
    libffi-dev libssl-dev \
    fontconfig xfonts-75dpi xfonts-base \
    ufw

  # Node tooling kadang dibutuhin untuk asset tools tertentu (tergantung setup)
  apt-get install -y --no-install-recommends nodejs npm || true
}

install_wkhtmltopdf() {
  if command -v wkhtmltopdf >/dev/null 2>&1; then
    log "wkhtmltopdf already installed: $(wkhtmltopdf --version || true)"
    return 0
  fi

  local os; os="$(os_info)"
  local id="${os%%:*}"
  local codename="${os#*:}"
  local arch; arch="$(dpkg --print-architecture)"

  [[ "$arch" == "amd64" ]] || die "wkhtmltopdf installer in this script targets amd64. Current arch: $arch"

  # Allow explicit override from env
  if [[ -n "${WKHTMLTOPDF_URL:-}" ]]; then
    log "Installing wkhtmltopdf from WKHTMLTOPDF_URL"
    wget -q "${WKHTMLTOPDF_URL}" -O /tmp/wkhtmltox.deb
    dpkg -i /tmp/wkhtmltox.deb || apt-get install -f -y
    command -v wkhtmltopdf >/dev/null 2>&1 || die "wkhtmltopdf install failed using WKHTMLTOPDF_URL"
    log "wkhtmltopdf installed: $(wkhtmltopdf --version || true)"
    return 0
  fi

  # Best-effort: use distro package for newer Ubuntu/Debian if available,
  # otherwise use pinned GitHub release packages for known codenames.
  log "Installing wkhtmltopdf (best effort for ${id}:${codename})"

  if [[ "$id" == "ubuntu" ]]; then
    case "$codename" in
      bionic)
        # matches your original approach but without forcing libssl1.1 from archives
        local url="https://github.com/wkhtmltopdf/wkhtmltopdf/releases/download/0.12.5/wkhtmltox_0.12.5-1.bionic_amd64.deb"
        wget -q "$url" -O /tmp/wkhtmltox.deb
        dpkg -i /tmp/wkhtmltox.deb || apt-get install -f -y
        ;;
      focal)
        # try focal build (0.12.6 is commonly available for focal)
        local url="https://github.com/wkhtmltopdf/wkhtmltopdf/releases/download/0.12.6/wkhtmltox_0.12.6-1.focal_amd64.deb"
        wget -q "$url" -O /tmp/wkhtmltox.deb
        dpkg -i /tmp/wkhtmltox.deb || apt-get install -f -y
        ;;
      jammy|noble|*)
        # for jammy/noble: avoid injecting libssl1.1; use repo package if available
        apt-get install -y wkhtmltopdf || true
        ;;
    esac
  else
    # Debian or other: try repo package
    apt-get install -y wkhtmltopdf || true
  fi

  command -v wkhtmltopdf >/dev/null 2>&1 || die "wkhtmltopdf is still not installed. Set WKHTMLTOPDF_URL in .env to force a known-good .deb."
  log "wkhtmltopdf installed: $(wkhtmltopdf --version || true)"
}

setup_ufw() {
  local enable="${ENABLE_UFW:-1}"
  [[ "$enable" == "1" ]] || { log "UFW setup skipped (ENABLE_UFW!=1)"; return 0; }

  local ssh_port="${SSH_PORT:-22}"
  local allow_http="${ALLOW_HTTP:-1}"
  local allow_https="${ALLOW_HTTPS:-1}"
  local allow_odoo="${ALLOW_ODOO_PORT:-0}"

  log "Configuring UFW"
  ufw allow "${ssh_port}/tcp" >/dev/null || true
  [[ "$allow_http" == "1" ]] && ufw allow 80/tcp >/dev/null || true
  [[ "$allow_https" == "1" ]] && ufw allow 443/tcp >/dev/null || true
  [[ "$allow_odoo" == "1" ]] && ufw allow 8069/tcp >/dev/null || true

  ufw --force enable >/dev/null || true
  ufw status verbose || true
}

main() {
  require_root
  load_env
  install_packages
  install_wkhtmltopdf
  setup_ufw
  log "Base dependencies ready"
}

main "$@"