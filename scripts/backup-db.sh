#!/usr/bin/env bash
# =============================================================================
# Arcway : sauvegarde logique chiffrée de la base (PRODUCTION)
# -----------------------------------------------------------------------------
# pg_dump chiffré à la volée avec « age » : le fichier en clair n'existe JAMAIS
# sur le disque. Seule la clé PUBLIQUE est nécessaire sur le serveur ; la clé
# privée reste hors ligne, ce qui limite l'impact d'une compromission du serveur.
#
# Sortie : $BACKUP_DIR/arcway-<base>-<AAAAMMJJTHHMMSSZ>.dump.age (+ .sha256)
# Rétention : suppression des sauvegardes plus anciennes que BACKUP_RETENTION_DAYS.
#
# Configuration (variables d'environnement)
#   PGHOST, PGPORT, PGDATABASE   cible (PGHOST et PGDATABASE requis)
#   PGUSER                       défaut : arcway_migrator
#   ARCWAY_DB_MIGRATOR_PASSWORD_FILE  fichier contenant le mot de passe
#   PGSSLMODE                    défaut : require (verify-full + PGSSLROOTCERT conseillé)
#   BACKUP_AGE_RECIPIENT         clé publique age (requis), ex. age1...
#   BACKUP_DIR                   défaut : /var/backups/arcway
#   BACKUP_RETENTION_DAYS        défaut : 30
#   BACKUP_MIN_BYTES             taille minimale plausible, défaut : 1024
#   BACKUP_AGE_IDENTITY_FILE     optionnel : clé privée pour un contrôle de
#                                déchiffrement (à n'utiliser que sur un poste de
#                                confiance, jamais sur le serveur de production)
#   BACKUP_POST_HOOK             optionnel : exécutable appelé avec le chemin du
#                                fichier final (copie hors site, notification)
#
# Planification (exemple cron, tous les jours à 02:00 UTC) :
#   0 2 * * * /opt/arcway/scripts/backup-db.sh >> /var/log/arcway-backup.log 2>&1
#
# Prérequis : pg_dump (version majeure >= serveur), age, sha256sum, find ; flock
# recommandé (évite deux sauvegardes simultanées).
# Codes de sortie : 0 succès ; 1 échec ; 64 configuration invalide.
# =============================================================================
set -Eeuo pipefail
umask 077

readonly SCRIPT_NAME="$(basename "$0")"

log() { printf '%s [%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SCRIPT_NAME" "$*"; }
die() { log "ERREUR : $*" >&2; exit 1; }
cfg() { log "CONFIGURATION : $*" >&2; exit 64; }

# --- Configuration -------------------------------------------------------------
: "${PGHOST:?PGHOST est requis}"
: "${PGDATABASE:?PGDATABASE est requis}"
export PGHOST PGDATABASE
export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER:-arcway_migrator}"
export PGSSLMODE="${PGSSLMODE:-require}"

BACKUP_DIR="${BACKUP_DIR:-/var/backups/arcway}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
BACKUP_MIN_BYTES="${BACKUP_MIN_BYTES:-1024}"
[[ -n "${BACKUP_AGE_RECIPIENT:-}" ]] || cfg "BACKUP_AGE_RECIPIENT est requis"
[[ "$BACKUP_RETENTION_DAYS" =~ ^[0-9]+$ && "$BACKUP_RETENTION_DAYS" -ge 1 ]] || cfg "BACKUP_RETENTION_DAYS invalide"

for tool in pg_dump pg_restore age sha256sum find; do
  command -v "$tool" >/dev/null 2>&1 || cfg "outil requis introuvable : $tool"
done

# Le mot de passe est lu depuis un fichier, jamais passé en argument.
if [[ -n "${ARCWAY_DB_MIGRATOR_PASSWORD_FILE:-}" ]]; then
  [[ -r "$ARCWAY_DB_MIGRATOR_PASSWORD_FILE" ]] || cfg "fichier de mot de passe illisible"
  PGPASSWORD="$(< "$ARCWAY_DB_MIGRATOR_PASSWORD_FILE")"
  export PGPASSWORD
fi

mkdir -p "$BACKUP_DIR"
[[ -w "$BACKUP_DIR" ]] || cfg "BACKUP_DIR n'est pas inscriptible : $BACKUP_DIR"

# --- Verrou : une seule sauvegarde à la fois ------------------------------------
if command -v flock >/dev/null 2>&1; then
  exec 9>"$BACKUP_DIR/.backup.lock"
  flock -n 9 || die "une sauvegarde est déjà en cours"
fi

# --- Fichiers ------------------------------------------------------------------
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
final_name="arcway-${PGDATABASE}-${timestamp}.dump.age"
final_path="$BACKUP_DIR/$final_name"
partial_path="$final_path.partial"

# Un échec ne laisse jamais de fichier partiel.
cleanup() { rm -f -- "$partial_path"; }
trap cleanup EXIT
trap 'die "interrompu à la ligne $LINENO"' ERR

# --- Sauvegarde ----------------------------------------------------------------
log "Début : base '$PGDATABASE' sur '$PGHOST' (utilisateur $PGUSER, sslmode $PGSSLMODE)"

# pipefail : un échec de pg_dump fait échouer tout le pipeline, même si age réussit.
pg_dump --format=custom --compress=6 --no-password --lock-wait-timeout=30s \
  | age --recipient "$BACKUP_AGE_RECIPIENT" --output "$partial_path"

size="$(wc -c < "$partial_path" | tr -d '[:space:]')"
[[ "$size" -ge "$BACKUP_MIN_BYTES" ]] || die "sauvegarde suspecte : $size octets (minimum $BACKUP_MIN_BYTES)"

# Publication atomique : le fichier final n'apparaît que complet.
mv -- "$partial_path" "$final_path"
(cd "$BACKUP_DIR" && sha256sum "$final_name" > "$final_name.sha256")
log "Sauvegarde écrite : $final_path ($size octets)"

# --- Contrôle de déchiffrement ---------
if [[ -n "${BACKUP_AGE_IDENTITY_FILE:-}" ]]; then
  [[ -r "$BACKUP_AGE_IDENTITY_FILE" ]] || die "BACKUP_AGE_IDENTITY_FILE illisible"
  age --decrypt --identity "$BACKUP_AGE_IDENTITY_FILE" "$final_path" | pg_restore --list >/dev/null \
    || die "la sauvegarde ne se déchiffre pas ou n'est pas un dump valide"
  log "Contrôle de déchiffrement et de structure : OK"
fi

# --- Rétention -----------------------------------------------------------------
# La sauvegarde du jour vient d'être écrite : elle n'est jamais éligible.
log "Rétention : suppression des fichiers de plus de $BACKUP_RETENTION_DAYS jours"
find "$BACKUP_DIR" -maxdepth 1 -type f \
  \( -name 'arcway-*.dump.age' -o -name 'arcway-*.dump.age.sha256' \) \
  -mtime +"$BACKUP_RETENTION_DAYS" -print -delete

# --- Crochet post-sauvegarde (copie hors site, notification) -------------------
if [[ -n "${BACKUP_POST_HOOK:-}" ]]; then
  [[ -x "$BACKUP_POST_HOOK" ]] || die "BACKUP_POST_HOOK n'est pas exécutable"
  "$BACKUP_POST_HOOK" "$final_path" || die "le crochet post-sauvegarde a échoué"
  log "Crochet post-sauvegarde : OK"
fi

log "Terminé"
