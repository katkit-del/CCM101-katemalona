#!/usr/bin/env bash
#
# automation-script.sh - VaultCloud health check + database backup
# CCM101 Laboratory 10 - Enterprise Cloud Architect
#
# What it does, in order:
#   1. Takes a lock so two runs can never overlap
#   2. Health-checks the app and database containers
#   3. Checks that the disk has enough free space
#   4. Dumps the Nextcloud database into a compressed .sql.gz file
#   5. Verifies the archive and stores a SHA-256 checksum next to it
#   6. Keeps only the newest KEEP backups (default 7), deletes the rest
#
# Exit code: 0 = success, 1 = a check or the backup failed.
# Settings can be overridden from the environment, e.g.  KEEP=14 ./automation-script.sh

set -Eeuo pipefail
umask 077                                   # backups are readable by the owner only
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="${BACKUP_DIR:-$SCRIPT_DIR/backups}"
DB_CONTAINER="${DB_CONTAINER:-vault-db}"
APP_CONTAINER="${APP_CONTAINER:-vault-app}"
KEEP="${KEEP:-7}"
MIN_FREE_MB="${MIN_FREE_MB:-500}"
LOCK_FILE="${TMPDIR:-/tmp}/vaultcloud-backup.lock"

STAMP="$(date +%F_%H-%M-%S)"
OUT_FILE="$BACKUP_DIR/vault_db_${STAMP}.sql.gz"
TMP_FILE=""

log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*"; }

discard_partial() {
  if [[ -n "$TMP_FILE" ]]; then rm -f -- "$TMP_FILE"; fi
}

die() { log "ERROR: $*"; discard_partial; exit 1; }

trap 'log "ERROR: unexpected failure near line $LINENO"; discard_partial; exit 1' ERR

mkdir -p "$BACKUP_DIR"

# --- 1. lock -----------------------------------------------------------
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  log "Another run is still in progress - exiting."
  exit 0
fi

log "=== VaultCloud backup started ==="

# --- 2. health check ---------------------------------------------------
for c in "$DB_CONTAINER" "$APP_CONTAINER"; do
  state="$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null)" || die "container '$c' not found"
  [[ "$state" == "running" ]] || die "container '$c' is '$state' (expected 'running')"
  log "OK   container $c is running"
done

health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$DB_CONTAINER")"
[[ "$health" == "healthy" ]] || die "database health is '$health' (expected 'healthy')"
log "OK   database reports healthy"

# --- 3. disk space -----------------------------------------------------
free_mb="$(df -Pm "$BACKUP_DIR" | awk 'NR==2 {print $4}')"
(( free_mb >= MIN_FREE_MB )) || die "only ${free_mb} MB free (need at least ${MIN_FREE_MB} MB)"
log "OK   ${free_mb} MB free on backup disk"

# --- 4. dump the database ---------------------------------------------
# The root password and DB name are read INSIDE the container, so no
# secret is ever written in this script or in the process list.
TMP_FILE="${OUT_FILE}.partial"
docker exec "$DB_CONTAINER" sh -c \
  'exec mariadb-dump --single-transaction --routines --triggers -uroot -p"$MARIADB_ROOT_PASSWORD" "$MARIADB_DATABASE"' \
  | gzip -9 > "$TMP_FILE"

# --- 5. verify, then publish the file ---------------------------------
gzip -t "$TMP_FILE" || die "archive is corrupt"
tables="$(zcat "$TMP_FILE" | grep -c '^CREATE TABLE' || true)"
(( tables > 0 )) || die "dump contains no tables - refusing to keep it"

mv -- "$TMP_FILE" "$OUT_FILE"
TMP_FILE=""
( cd "$BACKUP_DIR" && sha256sum "$(basename "$OUT_FILE")" > "$(basename "$OUT_FILE").sha256" )
log "OK   created $(basename "$OUT_FILE") ($(du -h "$OUT_FILE" | cut -f1), ${tables} tables)"

# --- 6. retention ------------------------------------------------------
mapfile -t old_files < <(ls -1t "$BACKUP_DIR"/vault_db_*.sql.gz | tail -n +"$((KEEP + 1))")
for f in "${old_files[@]}"; do
  rm -f -- "$f" "$f.sha256"
  log "OK   removed old backup $(basename "$f")"
done

log "=== Backup finished: $(ls -1 "$BACKUP_DIR"/vault_db_*.sql.gz | wc -l) backup(s) kept ==="
