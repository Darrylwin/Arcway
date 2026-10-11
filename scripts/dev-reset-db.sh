#!/usr/bin/env bash
# =============================================================================
# Arcway : réinitialisation de la base de DÉVELOPPEMENT LOCAL
# -----------------------------------------------------------------------------
# Détruit le volume PostgreSQL local, recrée les conteneurs et rejoue
# ops/db/init/01-roles.sql (création de arcway_migrator et arcway_app).
# Les tables sont ensuite créées par Flyway au prochain démarrage de
# l'application avec le profil « local ».
#
# Usage   : scripts/dev-reset-db.sh [--yes]
#   --yes : ne demande pas de confirmation
#
# Sécurité
#   - Refuse de tourner si ARCWAY_DB_URL ne vise pas localhost / 127.0.0.1.
#   - Refuse de tourner avec un profil Spring « prod » ou « migrate ».
#   - Exige de retaper le nom de la base, sauf avec --yes.
#   - Ne touche QUE le projet compose « arcway » de ce dépôt.
#
# Prérequis : docker compose v2, fichier .env.
# =============================================================================
set -Eeuo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() { printf '[%s] %s\n' "$SCRIPT_NAME" "$*"; }
die() { printf '[%s] ERREUR : %s\n' "$SCRIPT_NAME" "$*" >&2; exit 1; }
usage() { sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

ASSUME_YES=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes)  ASSUME_YES=true ;;
    -h|--help) usage; exit 0 ;;
    *)         usage >&2; exit 64 ;;
  esac
  shift
done

cd "$REPO_ROOT"

command -v docker >/dev/null 2>&1 || die "docker est introuvable"
docker compose version >/dev/null 2>&1 || die "docker compose v2 est requis"
[[ -f compose.yml ]] || die "compose.yml introuvable dans $REPO_ROOT"
[[ -f .env ]] || die ".env introuvable : cp .env.example .env puis remplacer les CHANGE_ME"

# Chargement de .env : fichier local de développement, non versionné.
set -a
# shellcheck disable=SC1091
source ./.env
set +a

# --- Garde-fous : on ne détruit JAMAIS autre chose qu'une base locale ---------
db_url="${ARCWAY_DB_URL:-}"
[[ -n "$db_url" ]] || die "ARCWAY_DB_URL n'est pas défini dans .env"

db_host="${db_url#jdbc:postgresql://}"
db_host="${db_host%%[:/?]*}"
case "$db_host" in
  localhost|127.0.0.1) ;;
  *) die "refus : ARCWAY_DB_URL vise '$db_host' (seuls localhost et 127.0.0.1 sont acceptés)" ;;
esac

case "${SPRING_PROFILES_ACTIVE:-}" in
  *prod*|*migrate*) die "refus : SPRING_PROFILES_ACTIVE contient un profil de production" ;;
esac

: "${POSTGRES_USER:?POSTGRES_USER est requis dans .env}"
: "${POSTGRES_DB:?POSTGRES_DB est requis dans .env}"

# --- Confirmation --------------------------------------------------------------
if [[ "$ASSUME_YES" != true ]]; then
  [[ -t 0 ]] || die "terminal non interactif : utiliser --yes"
  log "Toutes les données de la base locale '$POSTGRES_DB' vont être DÉTRUITES."
  read -r -p "Retaper le nom de la base pour confirmer : " answer
  [[ "$answer" == "$POSTGRES_DB" ]] || die "annulé"
fi

# --- Réinitialisation ----------------------------------------------------------
log "Arrêt des conteneurs et suppression du volume..."
docker compose down --volumes --remove-orphans

log "Démarrage des conteneurs (attente du healthcheck)..."
docker compose up --detach --wait --wait-timeout 90

# --- Vérification : les rôles existent et n'ont pas de privilège dangereux ----
psql_local() {
  docker compose exec -T postgres psql -X -v ON_ERROR_STOP=1 \
    -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tA -c "$1"
}

roles="$(psql_local "SELECT count(*) FROM pg_roles WHERE rolname IN ('arcway_app','arcway_migrator')")"
[[ "${roles//[[:space:]]/}" == "2" ]] || die "les rôles arcway_app / arcway_migrator n'ont pas été créés (voir les logs : docker compose logs postgres)"

dangerous="$(psql_local "SELECT count(*) FROM pg_roles WHERE rolname = 'arcway_app' AND (rolsuper OR rolbypassrls OR rolcreatedb OR rolcreaterole)")"
[[ "${dangerous//[[:space:]]/}" == "0" ]] || die "arcway_app possède un privilège interdit (superuser, BYPASSRLS, CREATEDB ou CREATEROLE)"

log "Base réinitialisée. Rôles arcway_migrator et arcway_app en place."
log "Étape suivante : ./mvnw spring-boot:run -Dspring-boot.run.profiles=local"
log "(Flyway créera le schéma au démarrage ; emails visibles sur http://localhost:${MAILPIT_UI_PORT:-8025})"
