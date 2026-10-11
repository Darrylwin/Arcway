#!/usr/bin/env bash
# =============================================================================
# Arcway : test de fumée après déploiement
# -----------------------------------------------------------------------------
# Vérifie qu'une instance fraîchement déployée est saine ET correctement
# verrouillée. Appelé par release.yml après le déploiement ; échoue (code 1) à la
# première anomalie constatée à la fin du passage.
#
# Usage
#   smoke-test.sh --base-url <url-api> [--management-url <url>] [--timeout <s>] [--full]
#
#   --base-url        URL publique de l'API (ex. https://api.arcway.example)
#   --management-url  URL d'Actuator (port de management distinct) ; défaut : base-url
#   --timeout         attente maximale de la readiness en secondes (défaut : 120)
#   --full            ajoute le scénario avec ÉCRITURE (inscription, connexion,
#                     profil, déconnexion). À réserver à la préproduction : il crée
#                     un compte de test. Nécessite jq.
#
# Contrôles par défaut (LECTURE SEULE, sans danger en production)
#   1. Attente de la readiness (processus ET base de données).
#   2. Liveness.
#   3. La santé n'expose aucun détail interne.
#   4. Actuator n'est pas exposé sur l'URL publique de l'API.
#   5. Route protégée sans jeton : 401 au format Problem Details, sans trace.
#   6. Connexion avec de faux identifiants : 401 (pas 500, pas de fuite).
#   7. Route inconnue : 404.
#   8. En-têtes de sécurité (nosniff, absence de X-Powered-By, HSTS en HTTPS).
#
# Prérequis : curl ; jq et openssl pour --full.
# Codes de sortie : 0 succès ; 1 anomalie ; 64 usage.
# =============================================================================
set -Eeuo pipefail

# shellcheck disable=SC2155
readonly SCRIPT_NAME="$(basename "$0")"
readonly API_PREFIX="/api/v1"

log()  { printf '[%s] %s\n' "$SCRIPT_NAME" "$*"; }
usage() { sed -n '2,33p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

# --- Arguments -----------------------------------------------------------------
BASE_URL=""; MANAGEMENT_URL=""; TIMEOUT=120; FULL=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url)       BASE_URL="${2:-}"; shift ;;
    --management-url) MANAGEMENT_URL="${2:-}"; shift ;;
    --timeout)        TIMEOUT="${2:-}"; shift ;;
    --full)           FULL=true ;;
    -h|--help)        usage; exit 0 ;;
    *)                usage >&2; exit 64 ;;
  esac
  shift
done

[[ -n "$BASE_URL" ]] || { usage >&2; exit 64; }
[[ "$BASE_URL" =~ ^https?:// ]] || { echo "URL invalide : $BASE_URL" >&2; exit 64; }
[[ "$TIMEOUT" =~ ^[0-9]+$ ]] || { echo "--timeout invalide" >&2; exit 64; }
BASE_URL="${BASE_URL%/}"
MANAGEMENT_URL="${MANAGEMENT_URL:-$BASE_URL}"
MANAGEMENT_URL="${MANAGEMENT_URL%/}"

command -v curl >/dev/null 2>&1 || { echo "curl est requis" >&2; exit 1; }
if [[ "$FULL" == true ]]; then
  command -v jq >/dev/null 2>&1 || { echo "jq est requis pour --full" >&2; exit 1; }
  command -v openssl >/dev/null 2>&1 || { echo "openssl est requis pour --full" >&2; exit 1; }
fi

# --- Outillage de test ---------------------------------------------------------
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
BODY="$WORKDIR/body"; HEADERS="$WORKDIR/headers"
STATUS=""; CHECKS=0; FAILURES=0

# request <méthode> <url> [arguments curl...] : renseigne STATUS, BODY, HEADERS.
# Un échec réseau donne STATUS=000.
request() {
  local method="$1" url="$2"; shift 2
  STATUS="$(curl --silent --show-error --max-time 10 --request "$method" \
    --output "$BODY" --dump-header "$HEADERS" --write-out '%{http_code}' \
    "$@" "$url" 2>/dev/null || true)"
  [[ -n "$STATUS" ]] || STATUS="000"
}

pass() { CHECKS=$((CHECKS + 1)); log "  OK   $1"; }
fail() { CHECKS=$((CHECKS + 1)); FAILURES=$((FAILURES + 1)); log "  ECHEC $1"; }

expect_status() { # <libellé> <regex de statuts acceptés>
  if [[ "$STATUS" =~ ^($2)$ ]]; then pass "$1 (HTTP $STATUS)"; else fail "$1 : HTTP $STATUS (attendu : $2)"; fi
}
expect_header() { # <libellé> <motif insensible à la casse>
  if grep -qiE "$2" "$HEADERS"; then pass "$1"; else fail "$1 : en-tête absent"; fi
}
expect_no_header() { # <libellé> <motif>
  if grep -qiE "$2" "$HEADERS"; then fail "$1 : en-tête présent"; else pass "$1"; fi
}
expect_body_lacks() { # <libellé> <motif>
  if grep -qE "$2" "$BODY"; then fail "$1 : motif interdit présent dans la réponse"; else pass "$1"; fi
}

JSON=(--header 'Content-Type: application/json' --header 'Accept: application/json')

# --- 1. Readiness -----------------------------------------------
log "Attente de la readiness (maximum ${TIMEOUT}s) : $MANAGEMENT_URL"
deadline=$(( $(date +%s) + TIMEOUT ))
while :; do
  request GET "$MANAGEMENT_URL/actuator/health/readiness"
  if [[ "$STATUS" == "200" ]] && grep -q '"status":"UP"' "$BODY"; then break; fi
  if (( $(date +%s) >= deadline )); then
    fail "readiness non atteinte après ${TIMEOUT}s (dernier HTTP $STATUS)"
    log "Échec : l'instance n'est pas prête. Contrôles suivants ignorés."
    exit 1
  fi
  sleep 3
done
pass "readiness UP (processus et base de données)"

# --- 2 à 8. Contrôles ----------------------------------------------------------
log "Contrôles de santé et d'exposition"

request GET "$MANAGEMENT_URL/actuator/health/liveness"
expect_status "liveness" "200"

request GET "$MANAGEMENT_URL/actuator/health"
expect_body_lacks "la santé n'expose aucun composant interne" '"components"|"details"'

if [[ "$MANAGEMENT_URL" != "$BASE_URL" ]]; then
  request GET "$BASE_URL/actuator/health"
  expect_status "Actuator absent de l'URL publique" "401|403|404"
fi

log "Contrôles de l'API"

request GET "$BASE_URL$API_PREFIX/me"
expect_status "route protégée sans jeton" "401"
expect_header "erreur au format Problem Details" '^content-type:.*application/problem\+json'
expect_body_lacks "aucune trace technique dans l'erreur" 'Exception|[[:space:]]at [a-z]+\.[a-z]+\.|org\.springframework|com\.darcode'

request POST "$BASE_URL$API_PREFIX/auth/login" "${JSON[@]}" \
  --data '{"email":"smoke-unknown@arcway.invalid","password":"not-a-real-password-0000"}'
expect_status "connexion avec de faux identifiants" "401"
expect_body_lacks "aucun détail sur l'existence du compte" 'not found|inconnu|unknown user|no such'

request GET "$BASE_URL$API_PREFIX/this-route-does-not-exist"
expect_status "route inconnue" "401|404"

log "En-têtes de sécurité"
request GET "$BASE_URL$API_PREFIX/me"
expect_header "X-Content-Type-Options: nosniff" '^x-content-type-options:[[:space:]]*nosniff'
expect_no_header "pas de X-Powered-By" '^x-powered-by:'
if [[ "$BASE_URL" == https://* ]]; then
  expect_header "Strict-Transport-Security (HTTPS)" '^strict-transport-security:'
fi

# --- Version déployée --------------------------------------------
request GET "$MANAGEMENT_URL/actuator/info"
if [[ "$STATUS" == "200" ]]; then
  log "Version déployée : $(tr -d '\n' < "$BODY" | head -c 300)"
fi

# --- Scénario complet avec écriture ------------------
if [[ "$FULL" == true ]]; then
  log "Scénario complet (crée un compte de test)"

  # HYPOTHÈSE : noms de champs des DTO (email, password, firstName, lastName,
  # accessToken, refreshToken).
  # À aligner avec RegisterRequest, LoginRequest, RefreshRequest et TokenResponse.
  smoke_email="smoke-$(date -u +%Y%m%d%H%M%S)-$RANDOM@${ARCWAY_SMOKE_EMAIL_DOMAIN:-smoke.arcway.invalid}"
  smoke_password="Sm-$(openssl rand -hex 16)-Aa1!"

  request POST "$BASE_URL$API_PREFIX/auth/register" "${JSON[@]}" \
    --data "$(jq -n --arg e "$smoke_email" --arg p "$smoke_password" \
      '{email:$e,password:$p,firstName:"Smoke",lastName:"Test"}')"
  expect_status "inscription" "200|201|204"

  request POST "$BASE_URL$API_PREFIX/auth/login" "${JSON[@]}" \
    --data "$(jq -n --arg e "$smoke_email" --arg p "$smoke_password" '{email:$e,password:$p}')"
  expect_status "connexion" "200"
  access_token="$(jq -r '.accessToken // empty' "$BODY" 2>/dev/null || true)"
  refresh_token="$(jq -r '.refreshToken // empty' "$BODY" 2>/dev/null || true)"

  if [[ -n "$access_token" ]]; then
    request GET "$BASE_URL$API_PREFIX/me" --header "Authorization: Bearer $access_token"
    expect_status "profil avec jeton valide" "200"
  else
    fail "jeton d'accès absent de la réponse de connexion"
  fi

  if [[ -n "$refresh_token" ]]; then
    request POST "$BASE_URL$API_PREFIX/auth/logout" "${JSON[@]}" \
      --data "$(jq -n --arg r "$refresh_token" '{refreshToken:$r}')"
    expect_status "déconnexion" "200|204"

    request POST "$BASE_URL$API_PREFIX/auth/refresh" "${JSON[@]}" \
      --data "$(jq -n --arg r "$refresh_token" '{refreshToken:$r}')"
    expect_status "refresh refusé après déconnexion" "401"
  else
    fail "jeton de refresh absent de la réponse de connexion"
  fi

  log "Compte de test créé (à anonymiser si besoin) : $smoke_email"
fi

# --- Bilan ---------------------------------------------------------------------
log "Bilan : $((CHECKS - FAILURES))/$CHECKS contrôles réussis"
if (( FAILURES > 0 )); then
  log "ÉCHEC : $FAILURES anomalie(s)"
  exit 1
fi
log "SUCCÈS"
