#!/usr/bin/env bash
set -e

# Sécurité : refuse de tourner hors local
if [ "$NODE_ENV" = "production" ] || [ "$SPRING_PROFILES_ACTIVE" = "prod" ]; then
  echo "ERREUR : Ce script de réinitialisation ne peut pas s'exécuter en production !"
  exit 1
fi

echo "Réinitialisation de la base de données locale Arcway..."

# Redémarrage propre des conteneurs via Docker Compose
docker compose down -v
docker compose up -d postgres

echo "Attente de la disponibilité de PostgreSQL..."
until docker exec arcway-postgres pg_isready -U postgres -d arcway_db; do
  sleep 2
done

echo "Base de données réinitialisée et prête !"
