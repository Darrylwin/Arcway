#!/usr/bin/env bash
# Initialisation des rôles PostgreSQL.
#
# Exécuté une seule fois par l'entrypoint de l'image postgres, à la création
# du volume, avec le compte administrateur (POSTGRES_USER) sur POSTGRES_DB.
#
# Modèle de privilèges (multi-tenancy, voir RLS) :
#   - migrator : propriétaire de la base et du schéma, utilisé par Flyway (DDL).
#   - app      : utilisé par l'application, DML uniquement. Ni propriétaire,
#                ni BYPASSRLS : il ne peut pas contourner les politiques RLS
#                ni modifier le schéma, même si l'application est compromise.
#
# Les droits sur les tables ne sont volontairement PAS accordés ici : les
# tables n'existent pas encore. Ils le seront explicitement dans les
# migrations Flyway, table par table.

set -euo pipefail

# Échec immédiat si une variable manque, plutôt qu'un rôle sans mot de passe.
: "${DB_MIGRATOR_USER:?DB_MIGRATOR_USER manquante}"
: "${DB_MIGRATOR_PASSWORD:?DB_MIGRATOR_PASSWORD manquante}"
: "${DB_APP_USER:?DB_APP_USER manquante}"
: "${DB_APP_PASSWORD:?DB_APP_PASSWORD manquante}"

psql -v ON_ERROR_STOP=1 \
     --username "$POSTGRES_USER" \
     --dbname "$POSTGRES_DB" \
     -v dbname="$POSTGRES_DB" \
     -v migrator_user="$DB_MIGRATOR_USER" \
     -v migrator_password="$DB_MIGRATOR_PASSWORD" \
     -v app_user="$DB_APP_USER" \
     -v app_password="$DB_APP_PASSWORD" <<'EOSQL'

CREATE ROLE :"migrator_user" LOGIN PASSWORD :'migrator_password'
    NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;

CREATE ROLE :"app_user" LOGIN PASSWORD :'app_password'
    NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;

-- Le migrator possède la base : il peut créer les extensions « trusted »
-- (citext, btree_gist, pg_trgm) sans être superuser. Il devient aussi
-- propriétaire du schéma public (PostgreSQL 15+).
ALTER DATABASE :"dbname" OWNER TO :"migrator_user";

REVOKE ALL ON DATABASE :"dbname" FROM PUBLIC;
GRANT CONNECT ON DATABASE :"dbname" TO :"migrator_user", :"app_user";

-- L'application peut voir le schéma, mais pas y créer d'objets.
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO :"app_user";

-- Une requête applicative ne doit pas pouvoir monopoliser la base.
ALTER ROLE :"app_user" SET statement_timeout = '5s';

EOSQL
