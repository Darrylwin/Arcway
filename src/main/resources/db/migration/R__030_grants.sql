-- =============================================================================
-- R__030 : privilèges de arcway_app
-- -----------------------------------------------------------------------------
-- Stratégie : on RÉVOQUE tout puis on ACCORDE explicitement. Rejouable sans dérive :
-- un droit retiré de ce fichier disparaît réellement de la base.
--
-- Le rôle applicatif ne possède aucun objet et n'a aucun DDL. Il n'a aucun DELETE
-- sur les tables qui ne sont jamais supprimées physiquement.
--
-- Les réglages du rôle (timeouts, search_path) sont dans ops/db/init/01-roles.sql :
-- ALTER ROLE exige CREATEROLE, que arcway_migrator n'a volontairement pas.
-- =============================================================================

-- Échec explicite et lisible si les rôles n'ont pas été créés.
DO
$$
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'arcway_app') THEN
            RAISE EXCEPTION 'Le rôle arcway_app est absent : exécuter ops/db/init/01-roles.sql avant les migrations';
        END IF;
    END
$$;

-- -----------------------------------------------------------------------------
-- 1. Remise à zéro
-- -----------------------------------------------------------------------------
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM arcway_app;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM arcway_app;
REVOKE CREATE ON SCHEMA public FROM arcway_app;

GRANT USAGE ON SCHEMA public TO arcway_app;

-- -----------------------------------------------------------------------------
-- 2. Identité (tables globales, sans RLS)
-- -----------------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE ON users TO arcway_app; -- pas de DELETE
GRANT SELECT, INSERT, UPDATE, DELETE ON auth_sessions, one_time_tokens TO arcway_app;

-- -----------------------------------------------------------------------------
-- 3. Tables jamais supprimées physiquement : pas de DELETE
-- -----------------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE ON
    organizations,
    memberships,
    invitations,
    teams,
    players,
    seasons,
    competitions,
    competition_teams,
    games,
    game_teams,
    awards
    TO arcway_app;

-- -----------------------------------------------------------------------------
-- 4. Tables dont des lignes peuvent être supprimées
--    La suppression de lignes d'une feuille VALIDATED exige une raison.
-- -----------------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE, DELETE ON team_staff, roster_entries, game_participations TO arcway_app;

-- -----------------------------------------------------------------------------
-- 5. Audit : append-only
-- -----------------------------------------------------------------------------
GRANT SELECT, INSERT ON audit_log TO arcway_app;

-- La séquence d'identité de audit_log : accordée par prudence ; sans effet
-- néfaste si PostgreSQL ne l'exige pas.
DO
$$
    DECLARE
        seq text := pg_get_serial_sequence('public.audit_log', 'id');
    BEGIN
        IF seq IS NOT NULL THEN
            EXECUTE format('GRANT USAGE ON SEQUENCE %s TO arcway_app', seq);
        END IF;
    END
$$;

-- --------------------------------------------
-- 6. Vue contractuelle
-- --------------------------------------------
GRANT SELECT ON v_official_player_games TO arcway_app;

-- -----------------------------------------------------------------------------
-- 7. Fonctions : EXECUTE retiré à PUBLIC, accordé au rôle applicatif
-- -----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION app_org_id() FROM PUBLIC;
REVOKE ALL ON FUNCTION app_user_id() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app_org_id() TO arcway_app;
GRANT EXECUTE ON FUNCTION app_user_id() TO arcway_app;
