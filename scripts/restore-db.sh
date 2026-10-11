#!/usr/bin/env bash
# =============================================================================
# Arcway : restauration d'une sauvegarde chiffrée (PRODUCTION / TEST MENSUEL)
# -----------------------------------------------------------------------------
# Déchiffre une sauvegarde produite par backup-db.sh et la restaure dans une base
# CIBLE NOMMÉE. Le script ne restaure jamais « par défaut » dans la base de
# production : la cible est toujours explicite.
#
# Usage
#   restore-db.sh --file <dump.age> --identity <cle-privee-age> --target-db <nom>
#                 [--replace] [--allow-production-target] [--list-only] [--yes]
#
#   --file                     sauvegarde chiffrée (.dump.age)
#   --identity                 clé privée age (fichier)
#   --target-db                base cible (minuscules, chiffres, underscore)
#   --replace                  supprime la cible si elle existe déjà
#   --allow-production-target  autorise la cible = ARCWAY_PRODUCTION_DB_NAME
#                              (reprise après sinistre uniquement)
#   --list-only                déchiffre et liste le contenu, sans rien restaurer
#   --yes                      pas de confirmation interactive
#
# Test de restauration mensuel : restaurer vers une base jetable
#   (ex. arcway_restore_test), contrôler les résultats affichés, puis la supprimer.
#
# Configuration (variables d'environnement)
#   PGHOST, PGPORT               serveur cible (PGHOST requis)
#   PGUSER                       compte d'ADMINISTRATION (superuser : création de
#                                base et des extensions citext / btree_gist)
#   ARCWAY_DB_ADMIN_PASSWORD_FILE  fichier du mot de passe (ou PGPASSFILE / PGPASSWORD)
#   PGSSLMODE                    défaut : require
#   ARCWAY_PRODUCTION_DB_NAME    défaut : arcway
#
# Prérequis
#   - Les rôles arcway_migrator et arcway_app existent sur le serveur cible
#     (ops/db/init/01-roles.sql). Les rôles ne font pas partie du dump.
#   - psql et pg_restore (version majeure >= celle du dump), age, sha256sum.
# =============================================================================
set -Eeuo pipefail
umask 077

# shellcheck disable=SC2155
readonly SCRIPT_NAME="$(basename "$0")"

log() { printf '%s [%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SCRIPT_NAME" "$*"; }
die() { log "ERREUR : $*" >&2; exit 1; }
usage() { sed -n '2,36p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

# --- Arguments -----------------------------------------------------------------
DUMP_FILE=""; IDENTITY_FILE=""; TARGET_DB=""
REPLACE=false; ALLOW_PROD=false; LIST_ONLY=false; ASSUME_YES=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file)                    DUMP_FILE="${2:-}"; shift ;;
    --identity)                IDENTITY_FILE="${2:-}"; shift ;;
    --target-db)               TARGET_DB="${2:-}"; shift ;;
    --replace)                 REPLACE=true ;;
    --allow-production-target) ALLOW_PROD=true ;;
    --list-only)               LIST_ONLY=true ;;
    --yes|-y)                  ASSUME_YES=true ;;
    -h|--help)                 usage; exit 0 ;;
    *)                         usage >&2; exit 64 ;;
  esac
  shift
done

[[ -n "$DUMP_FILE" && -r "$DUMP_FILE" ]] || { usage >&2; die "--file manquant ou illisible"; }
[[ -n "$IDENTITY_FILE" && -r "$IDENTITY_FILE" ]] || { usage >&2; die "--identity manquant ou illisible"; }
if [[ "$LIST_ONLY" != true ]]; then
  [[ -n "$TARGET_DB" ]] || { usage >&2; die "--target-db est requis"; }
  # Nom restreint : il est ensuite quoté comme identifiant SQL par psql.
  [[ "$TARGET_DB" =~ ^[a-z][a-z0-9_]{0,62}$ ]] || die "nom de base invalide : '$TARGET_DB'"
fi

for tool in psql pg_restore age sha256sum; do
  command -v "$tool" >/dev/null 2>&1 || die "outil requis introuvable : $tool"
done

# --- Connexion -----------------------------------------------------------------
if [[ "$LIST_ONLY" != true ]]; then
  : "${PGHOST:?PGHOST est requis}"
  export PGHOST
  export PGPORT="${PGPORT:-5432}"
  : "${PGUSER:?PGUSER (compte d\'administration) est requis}"
  export PGUSER
  export PGSSLMODE="${PGSSLMODE:-require}"
  if [[ -n "${ARCWAY_DB_ADMIN_PASSWORD_FILE:-}" ]]; then
    [[ -r "$ARCWAY_DB_ADMIN_PASSWORD_FILE" ]] || die "fichier de mot de passe illisible"
    PGPASSWORD="$(< "$ARCWAY_DB_ADMIN_PASSWORD_FILE")"
    export PGPASSWORD
  fi
fi

# --- Intégrité du fichier ------------------------------------------------------
if [[ -f "$DUMP_FILE.sha256" ]]; then
  (cd "$(dirname "$DUMP_FILE")" && sha256sum --check --status "$(basename "$DUMP_FILE").sha256") \
    || die "somme de contrôle invalide : fichier corrompu ou modifié"
  log "Somme de contrôle : OK"
else
  log "ATTENTION : pas de fichier .sha256, l'intégrité n'est pas vérifiée"
fi

# --- Mode liste seule ----------------------------------------------------------
if [[ "$LIST_ONLY" == true ]]; then
  age --decrypt --identity "$IDENTITY_FILE" "$DUMP_FILE" | pg_restore --list
  exit 0
fi

# --- Garde-fous sur la cible ---------------------------------------------------
production_db="${ARCWAY_PRODUCTION_DB_NAME:-arcway}"
if [[ "$TARGET_DB" == "$production_db" && "$ALLOW_PROD" != true ]]; then
  die "refus : '$TARGET_DB' est la base de production (ajouter --allow-production-target en cas de sinistre)"
fi

psql_admin() { psql -X -v ON_ERROR_STOP=1 --no-password -d postgres "$@"; }

role_count="$(psql_admin -tA -c "SELECT count(*) FROM pg_roles WHERE rolname IN ('arcway_app','arcway_migrator')")"
[[ "${role_count//[[:space:]]/}" == "2" ]] \
  || die "les rôles arcway_app et arcway_migrator n'existent pas sur ce serveur : exécuter d'abord ops/db/init/01-roles.sql"

exists="$(psql_admin -v target="$TARGET_DB" -tA <<< "SELECT 1 FROM pg_database WHERE datname = :'target'")"

if [[ -n "${exists//[[:space:]]/}" ]]; then
  [[ "$REPLACE" == true ]] || die "la base '$TARGET_DB' existe déjà (utiliser --replace pour la remplacer)"
fi

# --- Confirmation --------------------------------------------------------------
if [[ "$ASSUME_YES" != true ]]; then
  [[ -t 0 ]] || die "terminal non interactif : utiliser --yes"
  log "Cible : base '$TARGET_DB' sur '$PGHOST'."
  [[ -n "${exists//[[:space:]]/}" ]] && log "ELLE EXISTE ET SERA SUPPRIMÉE PUIS RECRÉÉE."
  read -r -p "Retaper le nom de la base pour confirmer : " answer
  [[ "$answer" == "$TARGET_DB" ]] || die "annulé"
fi

# --- Recréation de la base cible -----------------------------------------------
if [[ -n "${exists//[[:space:]]/}" ]]; then
  log "Suppression de '$TARGET_DB'..."
  psql_admin -v target="$TARGET_DB" <<< 'DROP DATABASE :"target" WITH (FORCE)'
fi

log "Création de '$TARGET_DB' (propriétaire : arcway_migrator)..."
psql_admin -v target="$TARGET_DB" <<< 'CREATE DATABASE :"target" OWNER arcway_migrator ENCODING UTF8'

# --- Restauration --------------------------------------------------------------
# Propriété et droits sont restaurés tels que sauvegardés (pas de --no-owner).
# --single-transaction + --exit-on-error : tout ou rien.
log "Restauration en cours..."
if ! age --decrypt --identity "$IDENTITY_FILE" "$DUMP_FILE" \
     | pg_restore --dbname="$TARGET_DB" --no-password --exit-on-error --single-transaction; then
  die "la restauration a échoué : la base '$TARGET_DB' est vide ou partielle, ne pas l'utiliser"
fi

# --- Droits au niveau de la base -----------------------
psql -X -v ON_ERROR_STOP=1 --no-password -d "$TARGET_DB" -v target="$TARGET_DB" <<'SQL'
REVOKE ALL ON DATABASE :"target" FROM PUBLIC;
GRANT CONNECT ON DATABASE :"target" TO arcway_app;
GRANT USAGE ON SCHEMA public TO arcway_app;
ANALYZE;
SQL

# --- Contrôles de cohérence --------------------------
log "Contrôles :"
psql -X -v ON_ERROR_STOP=1 --no-password -d "$TARGET_DB" -tA <<'SQL' | while IFS='|' read -r label value; do log "  $label : $value"; done
SELECT 'tables', count(*) FROM pg_tables WHERE schemaname = 'public';
SELECT 'tables avec RLS activée', count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relrowsecurity;
SELECT 'dernière migration Flyway', coalesce((SELECT version FROM flyway_schema_history WHERE success ORDER BY installed_rank DESC LIMIT 1), 'aucune');
SELECT 'utilisateurs', count(*) FROM users;
SELECT 'organisations', count(*) FROM organizations;
SQL

log "Restauration terminée : '$TARGET_DB'"
