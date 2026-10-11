#!/usr/bin/env bash
set -e

BACKUP_FILE="$1"
TARGET_DB_URL="$2"

if [ -z "$BACKUP_FILE" ] || [ -z "$TARGET_DB_URL" ]; then
  echo "Usage: $0 <chemin_backup_chiffré> <url_jdbc_cible>"
  exit 1
fi

echo "Restauration de la base de données..."

# Déchiffrement, décompression et réinjection dans la base cible
openssl enc -aes-256-cbc -d -pass "pass:${BACKUP_ENCRYPTION_KEY}" -in "$BACKUP_FILE" | gunzip | psql "$TARGET_DB_URL"

echo "Restauration terminée avec succès !"
