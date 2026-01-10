#!/bin/bash
set -e

LOG_FILE="/opt/odoo18/client.log"
ODOO_SERVICE="odoo18"

DB_HOST="IP_VM_DB" # Ganti Bang
DB_USER="odoo18"

FILESTORE_BASE="/opt/odoo18/.local/share/Odoo/filestore"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

fail() {
  log "ERROR: $1"
  echo "ERROR: $1"
  exit 1
}

pause() {
  read -p "Tekan ENTER untuk lanjut..."
}

# ======================
# PILIH DB SUMBER
# ======================
echo "== Pilih DB sumber (template) =="
mapfile -t DBS < <(psql -h $DB_HOST -U $DB_USER -d postgres -tAc \
"SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname;")

select SRC_DB in "${DBS[@]}"; do
  [ -n "$SRC_DB" ] && break
done

# ======================
# NAMA DB BARU
# ======================
read -p "Nama DB baru: " NEW_DB
NEW_DB=$(echo "$NEW_DB" | tr '[:upper:]' '[:lower:]')

# ======================
# PILIH FILESTORE
# ======================
echo
echo "== Pilih filestore sumber =="
mapfile -t STORES < <(ls -1 "$FILESTORE_BASE")

select SRC_FILESTORE in "${STORES[@]}"; do
  [ -n "$SRC_FILESTORE" ] && break
done

# ======================
# PASSWORD DB
# ======================
read -s -p "Password DB odoo18: " DB_PASS
echo
export PGPASSWORD="$DB_PASS"

TARGET_FILESTORE="$FILESTORE_BASE/$NEW_DB"
SRC_FILESTORE_PATH="$FILESTORE_BASE/$SRC_FILESTORE"

# ======================
# KONFIRMASI
# ======================
echo
echo "=============================="
echo "DB sumber       : $SRC_DB"
echo "DB baru         : $NEW_DB"
echo "Filestore       : $SRC_FILESTORE"
echo "=============================="
read -p "Lanjut buat client? (y/N): " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || exit 0

log "START create client $NEW_DB"

# ======================
# VALIDASI
# ======================
psql -h $DB_HOST -U $DB_USER -d postgres -tAc \
"SELECT 1 FROM pg_database WHERE datname='$NEW_DB'" | grep -q 1 \
&& fail "DB target sudah ada"

[ -d "$SRC_FILESTORE_PATH" ] || fail "Filestore sumber tidak ada"
[ -d "$TARGET_FILESTORE" ] && fail "Filestore target sudah ada"

# ======================
# EXECUTION
# ======================
systemctl stop $ODOO_SERVICE
log "Odoo stopped"

createdb -h $DB_HOST -U $DB_USER "$NEW_DB"
pg_dump -h $DB_HOST -U $DB_USER "$SRC_DB" | psql -h $DB_HOST -U $DB_USER "$NEW_DB"
log "DB cloned from $SRC_DB"

cp -r "$SRC_FILESTORE_PATH" "$TARGET_FILESTORE"

# Anti nested filestore
if [ -d "$TARGET_FILESTORE/$SRC_FILESTORE" ]; then
  rm -rf "$TARGET_FILESTORE"
  dropdb -h $DB_HOST -U $DB_USER "$NEW_DB"
  fail "Filestore nested (SALAH STRUKTUR)"
fi

chown -R odoo18:odoo18 "$TARGET_FILESTORE"
chmod -R 750 "$TARGET_FILESTORE"
log "Filestore OK"

systemctl start $ODOO_SERVICE
unset PGPASSWORD

log "SUCCESS client $NEW_DB created"
echo "✅ Client '$NEW_DB' berhasil dibuat"
