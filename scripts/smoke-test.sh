#!/usr/bin/env bash
set -e

API_URL="${ARCWAY_API_URL:-http://localhost:8080}"

echo "Lancement des smoke tests sur $API_URL..."

# 1. Vérification de la santé / readiness de l'application (Actuator)
STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$API_URL/actuator/health/readiness")

if [ "$STATUS_CODE" -eq 200 ]; then
  echo "[OK] L'application est prête (Readiness probe OK)."
else
  echo "[ERREUR] L'application ne répond pas correctement (Code HTTP : $STATUS_CODE)"
  exit 1
fi

echo "Tous les smoke tests ont réussi avec succès !"
