-- =============================================================================
-- V002 : fonctions d'aide au contexte de session
-- -----------------------------------------------------------------------------
-- Lisent les variables posées par l'application au début de chaque transaction :
--   app.org_id  : organisation active
--   app.user_id : utilisateur authentifié
--
-- Règles
--   - Les politiques RLS appellent ces fonctions et ne castent JAMAIS
--     current_setting directement.
--   - NULLIF(..., '') est indispensable : sur une connexion déjà utilisée, une
--     variable locale terminée vaut '', et ''::uuid lève une erreur.
--   - Sans contexte, le résultat est NULL : la RLS renvoie zéro ligne en lecture
--     et une erreur en écriture.
--   - LANGUAGE sql : la fonction est inlinée par le planificateur ; STABLE est
--     requis pour cela.
--   - Pas de SECURITY DEFINER.
--
-- Droits : EXECUTE est révoqué à PUBLIC et accordé à arcway_app dans
-- R__030_grants.sql.
-- =============================================================================

CREATE OR REPLACE FUNCTION app_org_id()
    RETURNS uuid
    LANGUAGE sql
    STABLE
AS
$$
SELECT NULLIF(current_setting('app.org_id', true), '')::uuid
$$;

CREATE OR REPLACE FUNCTION app_user_id()
    RETURNS uuid
    LANGUAGE sql
    STABLE
AS
$$
SELECT NULLIF(current_setting('app.user_id', true), '')::uuid
$$;
