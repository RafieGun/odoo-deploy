#!/bin/bash
set -e

echo "🐘 [01] pgAdmin4 Web setup (install only)"

# ===== SYSTEM DEPS =====
apt update
apt install -y \
  curl \
  gnupg \
  lsb-release \
  ca-certificates

# ===== PGADMIN GPG KEY =====
echo "🔑 Installing pgAdmin GPG key"
rm -f /etc/apt/trusted.gpg.d/pgadmin.gpg

curl -fsSL https://www.pgadmin.org/static/packages_pgadmin_org.pub \
| gpg --dearmor \
| tee /etc/apt/trusted.gpg.d/pgadmin.gpg > /dev/null

# ===== PGADMIN REPO =====
echo "📦 Adding pgAdmin repository"
echo "deb https://ftp.postgresql.org/pub/pgadmin/pgadmin4/apt/$(lsb_release -cs) pgadmin4 main" \
> /etc/apt/sources.list.d/pgadmin4.list

# ===== INSTALL PGADMIN WEB =====
apt update
apt install -y pgadmin4-web

# ===== MANUAL STEP INFO =====
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ pgAdmin4 Web INSTALLED (setup NOT run)"
echo ""
echo "👉 NEXT STEP (MANUAL, COPY & PASTE):"
echo ""
echo "   /usr/pgadmin4/bin/setup-web.sh"
echo ""
echo "ℹ️  This step is INTERACTIVE (email & password)"
echo "🌐 After setup access:"
echo "   http://<IP_OR_DOMAIN>/pgadmin4"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
