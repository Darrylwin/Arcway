-- Script d'initialisation des rôles PostgreSQL exécuté lors du démarrage du conteneur de base de données.

-- Rôle de migration (propriétaire des objets)
DO
$$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'arcway_migrator') THEN
            CREATE ROLE arcway_migrator WITH LOGIN PASSWORD 'arcway_migrator_dev_password';
        END IF;
    END
$$;

-- Rôle applicatif (accès DML strict sous RLS, ni superuser ni BYPASSRLS)
DO
$$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'arcway_app') THEN
            CREATE ROLE arcway_app WITH LOGIN PASSWORD 'arcway_app_dev_password'
                NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE;
        END IF;
    END
$$;

-- Configuration des timeouts pour le rôle applicatif
ALTER ROLE arcway_app SET statement_timeout = '5s';
ALTER ROLE arcway_app SET lock_timeout = '3s';
ALTER ROLE arcway_app SET idle_in_transaction_session_timeout = '15s';
