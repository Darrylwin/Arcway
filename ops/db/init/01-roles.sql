-- -----------------------------------------------------------------------------
-- Arcway : initialisation du cluster PostgreSQL
-- -----------------------------------------------------------------------------
-- Rôle du fichier
--   Seul endroit où les RÔLES sont créés. Les rôles sont des objets de cluster :
--   ils ne passent donc pas par Flyway. Ce fichier ne crée ni table ni droit sur
--   table (les droits sont dans R__030_grants.sql).
--
-- Rôles
--   arcway_migrator : propriétaire des objets. Utilisé UNIQUEMENT par l'étape
--                     Flyway et les procédures d'exploitation. Jamais par
--                     l'application en fonctionnement.
--   arcway_app      : rôle de l'application. Ne possède aucun objet, aucun DDL,
--                     ni SUPERUSER, ni BYPASSRLS : la RLS s'applique toujours.
--
-- Exécution
--   - Développement : monté dans /docker-entrypoint-initdb.d.
--     Exécuté une seule fois, à l'initialisation du volume.
--   - Production    : exécuté une fois par l'exploitant avec un compte
--     d'administration : psql -v ON_ERROR_STOP=1 -d arcway -f 01-roles.sql
--   - Tests         : rejoué par PostgresContainerConfig.
--
-- Idempotence
--   Rejouable sans erreur : un rôle existant voit seulement son mot de passe et
--   ses réglages resynchronisés.

\set ON_ERROR_STOP on

-- Lecture des secrets depuis l'environnement. Si une variable est absente,
-- psql échoue ici : on ne crée jamais un rôle avec un mot de passe vide.
\getenv migrator_password ARCWAY_DB_MIGRATOR_PASSWORD
\getenv app_password ARCWAY_DB_APP_PASSWORD

\if :{?migrator_password}
\else
\echo 'ARCWAY_DB_MIGRATOR_PASSWORD est requis'
\quit 1
\endif
\if :{?app_password}
\else
\echo 'ARCWAY_DB_APP_PASSWORD est requis'
\quit 1
\endif

-- -----------------------------------------------------------------------------
-- 1. Création des rôles
-- -----------------------------------------------------------------------------
SELECT format(
           'CREATE ROLE arcway_migrator LOGIN PASSWORD %L NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE NOREPLICATION',
           :'migrator_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'arcway_migrator')
\gexec

SELECT format(
           'CREATE ROLE arcway_app LOGIN PASSWORD %L NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE NOREPLICATION',
           :'app_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'arcway_app')
\gexec

-- Resynchronisation des mots de passe (rotation : rejouer le script).
SELECT format('ALTER ROLE arcway_migrator PASSWORD %L', :'migrator_password')
\gexec
SELECT format('ALTER ROLE arcway_app PASSWORD %L', :'app_password')
\gexec

-- -----------------------------------------------------------------------------
-- 2. Propriété de la base et du schéma
--    arcway_migrator doit posséder les objets : le propriétaire d'une table
--    contourne la RLS, c'est précisément pourquoi arcway_app ne doit RIEN posséder.
--    Les extensions citext et btree_gist sont « trusted » : le
--    propriétaire de la base peut les créer sans être superuser.
-- -----------------------------------------------------------------------------
SELECT format('ALTER DATABASE %I OWNER TO arcway_migrator', current_database())
\gexec
ALTER SCHEMA public OWNER TO arcway_migrator;

-- -----------------------------------------------------------------------------
-- 3. Fermeture des accès par défaut
-- -----------------------------------------------------------------------------
SELECT format('REVOKE ALL ON DATABASE %I FROM PUBLIC', current_database())
\gexec
REVOKE ALL ON SCHEMA public FROM PUBLIC;

SELECT format('GRANT CONNECT ON DATABASE %I TO arcway_app', current_database())
\gexec
GRANT USAGE ON SCHEMA public TO arcway_app;

-- -----------------------------------------------------------------------------
-- 4. Réglages du rôle applicatif
--    Posés ICI et non dans Flyway : ALTER ROLE exige CREATEROLE, que
--    arcway_migrator n'a volontairement pas.
--    Les routes d'analytique peuvent relever statement_timeout localement
--    (SET LOCAL) dans leur transaction.
-- -----------------------------------------------------------------------------
ALTER ROLE arcway_app SET statement_timeout = '5s';
ALTER ROLE arcway_app SET lock_timeout = '3s';
ALTER ROLE arcway_app SET idle_in_transaction_session_timeout = '15s';
-- search_path figé : évite le détournement de fonctions par un schéma intrus.
ALTER ROLE arcway_app SET search_path = public;

ALTER ROLE arcway_migrator SET search_path = public;
