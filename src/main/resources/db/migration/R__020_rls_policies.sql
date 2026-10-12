-- =============================================================================
-- R__020 : sécurité au niveau ligne, répétable et idempotente
-- -----------------------------------------------------------------------------
-- Principes
--   - TOUTE table portant organization_id a la RLS activée et au moins une politique.
--     La boucle sur le catalogue rend l'oubli impossible pour une nouvelle table.
--   - arcway_app n'est ni propriétaire, ni superuser, ni BYPASSRLS : les politiques
--     s'appliquent. Le propriétaire (arcway_migrator) les contourne par défaut ; on ne
--     force PAS la RLS (FORCE) car les migrations, le seed et la procédure de purge
--     d'une organisation en dépendent.
--   - Les politiques utilisent les fonctions app_org_id() / app_user_id() et ne
--     castent JAMAIS current_setting directement.
--   - Sans contexte : zéro ligne en lecture, ERREUR en écriture.
--     Le système échoue fermé.
--   - Aucune politique DELETE sur organizations, memberships et audit_log : suppression
--     interdite.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Activation + politique générique pol_tenant_isolation
--    Appliquée à toute table portant organization_id, sauf memberships et audit_log.
-- -----------------------------------------------------------------------------
DO
$$
    DECLARE
        t record;
    BEGIN
        FOR t IN
            SELECT c.relname AS table_name
            FROM pg_class c
                     JOIN pg_namespace n ON n.oid = c.relnamespace
                     JOIN pg_attribute a ON a.attrelid = c.oid
                AND a.attname = 'organization_id'
                AND a.attnum > 0
                AND NOT a.attisdropped
            WHERE n.nspname = 'public'
              AND c.relkind IN ('r', 'p')
            ORDER BY c.relname
            LOOP
                EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t.table_name);

                IF t.table_name IN ('memberships', 'audit_log') THEN
                    -- Cas particuliers : jamais de politique générique (rejeu sûr).
                    EXECUTE format('DROP POLICY IF EXISTS pol_tenant_isolation ON public.%I', t.table_name);
                ELSE
                    EXECUTE format('DROP POLICY IF EXISTS pol_tenant_isolation ON public.%I', t.table_name);
                    EXECUTE format(
                        'CREATE POLICY pol_tenant_isolation ON public.%I FOR ALL '
                            'USING (organization_id = app_org_id()) '
                            'WITH CHECK (organization_id = app_org_id())',
                        t.table_name);
                END IF;
            END LOOP;
    END
$$;

-- ---------------------------------------------
-- 2. organizations
-- ---------------------------------------------
ALTER TABLE organizations
    ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_organizations_select ON organizations;
DROP POLICY IF EXISTS pol_organizations_insert ON organizations;
DROP POLICY IF EXISTS pol_organizations_update ON organizations;

-- Lecture : l'organisation active, OU toute organisation où l'utilisateur courant
-- a une appartenance active.
CREATE POLICY pol_organizations_select ON organizations
    FOR SELECT
    USING (id = app_org_id()
    OR EXISTS (SELECT 1
               FROM memberships m
               WHERE m.organization_id = organizations.id
                 AND m.user_id = app_user_id()
                 AND m.ended_at IS NULL));

-- Création : l'application génère l'UUID et le pose comme app.org_id AVANT d'insérer.
CREATE POLICY pol_organizations_insert ON organizations
    FOR INSERT
    WITH CHECK (id = app_org_id());

CREATE POLICY pol_organizations_update ON organizations
    FOR UPDATE
    USING (id = app_org_id())
    WITH CHECK (id = app_org_id());

-- -----------------------------------------------------------------------------
-- 3. memberships
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS pol_memberships_select ON memberships;
DROP POLICY IF EXISTS pol_memberships_insert ON memberships;
DROP POLICY IF EXISTS pol_memberships_update ON memberships;

-- Lecture : celles de l'organisation active, OU les siennes.
CREATE POLICY pol_memberships_select ON memberships
    FOR SELECT
    USING (organization_id = app_org_id() OR user_id = app_user_id());

CREATE POLICY pol_memberships_insert ON memberships
    FOR INSERT
    WITH CHECK (organization_id = app_org_id());

CREATE POLICY pol_memberships_update ON memberships
    FOR UPDATE
    USING (organization_id = app_org_id())
    WITH CHECK (organization_id = app_org_id());

-- -----------------------------------------------------------------------------
-- 4. audit_log : lecture et insertion seulement, dans l'organisation active
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS pol_audit_log_select ON audit_log;
DROP POLICY IF EXISTS pol_audit_log_insert ON audit_log;

CREATE POLICY pol_audit_log_select ON audit_log
    FOR SELECT
    USING (organization_id = app_org_id());

CREATE POLICY pol_audit_log_insert ON audit_log
    FOR INSERT
    WITH CHECK (organization_id = app_org_id());
