#!/usr/bin/env bash
set -e

BACKUP_DIR="/var/backups/arcway"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/arcway_backup_$TIMESTAMP.sql.gz.enc"

mkdir -p "$BACKUP_DIR"

echo "Démarrage de la sauvegarde de la base de données Arcway..."

# Dump compressé puis chiffré (nécessite OPENSSL_KEY défini dans l'environnement)
pg_dump "$ARCWAY_DB_URL" | gzip | openssl enc -aes-256-cbc -salt -pass "pass:${BACKUP_ENCRYPTION_KEY}" -out "$BACKUP_FILE"

echo "Sauvegarde réussie : $BACKUP_FILE"
