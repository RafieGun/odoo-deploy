#!/bin/bash
set -e

# ===== SAFETY CHECK =====
if [[ $EUID -ne 0 ]]; then
  echo "❌ Run this script as root"
  exit 1
fi

# ===== LOAD ENV =====
if [ ! -f ".env" ]; then
  echo "❌ .env file not found"
  echo "👉 copy .env.example to .env"
  exit 1
fi

source .env

echo "🚀 Starting Odoo deployment for $DOMAIN"
echo "----------------------------------------"

# ===== RUN ALL SCRIPTS =====
for script in scripts/*.sh; do
  echo "▶ Running $script"
  bash "$script"
done

echo "✅ Deployment finished for $DOMAIN"
