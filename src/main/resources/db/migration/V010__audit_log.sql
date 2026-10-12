-- =============================================================================
-- V010 : traçabilité
-- -----------------------------------------------------------------------------
-- UN SEUL mécanisme de trigger métier : la trace des corrections.
-- audit_log est APPEND-ONLY. Historique conservé aussi longtemps que
-- l'organisation existe.
--
-- Ce que les triggers NE font PAS : valider une feuille, contrôler une transition
-- d'état, mettre à jour updated_at, contrôler QUI agit. Ces responsabilités sont
-- applicatives.
-- =============================================================================

CREATE TABLE audit_log
(
    id              bigint GENERATED ALWAYS AS IDENTITY,
    organization_id uuid        NOT NULL,
    actor_user_id   uuid,                 -- app_user_id() au moment de l'écriture
    entity_type     text        NOT NULL, -- nom de table (« game_participations »)
    entity_id       uuid        NOT NULL,
    action          text        NOT NULL, -- INSERT, UPDATE, DELETE
    before_data     jsonb,
    after_data      jsonb,
    reason          text,
    created_at      timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT pk_audit_log PRIMARY KEY (id),
    CONSTRAINT fk_audit_log_organization FOREIGN KEY (organization_id)
        REFERENCES organizations (id) ON DELETE RESTRICT,
    CONSTRAINT fk_audit_log_actor FOREIGN KEY (actor_user_id)
        REFERENCES users (id) ON DELETE RESTRICT,
    CONSTRAINT ck_audit_log_action CHECK (action ~ '^[A-Z][A-Z0-9_]{2,59}$')
);

CREATE INDEX ix_audit_log_entity ON audit_log (organization_id, entity_type, entity_id, created_at DESC);

-- -----------------------------------------------------------------------------
-- audit_row_change() : fonction de trigger, SANS SECURITY DEFINER.
--
-- Contexte lu : app.change_reason et app_user_id().
--
-- Règles par table
--   memberships         : insertion, ou changement de role / scope_all_teams /
--                         ended_at / ended_by_user_id. Raison facultative.
--   game_teams          : insertion, ou changement de score / forfait / statut de
--                         feuille / dérogation de points, ou toute modification d'une
--                         feuille VALIDATED. Raison OBLIGATOIRE si l'ancien statut
--                         est VALIDATED.
--   game_participations : UNIQUEMENT si la feuille parente est VALIDATED. Raison OBLIGATOIRE.
--
-- Raison obligatoire et absente : SQLSTATE Z1001, message stable
-- ARCWAY_CORRECTION_REASON_REQUIRED.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION audit_row_change()
    RETURNS trigger
    LANGUAGE plpgsql
    SET search_path = public
AS
$$
DECLARE
    v_old             jsonb;
    v_new             jsonb;
    v_row             jsonb;
    v_reason          text    := NULLIF(btrim(current_setting('app.change_reason', true)), '');
    v_audited         boolean := false;
    v_reason_required boolean := false;
    v_parent_status   stats_status;
BEGIN
    -- OLD n'existe pas pour INSERT et NEW n'existe pas pour DELETE : jamais de
    -- référence directe en dehors de ces gardes.
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        v_old := to_jsonb(OLD);
    END IF;
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        v_new := to_jsonb(NEW);
    END IF;
    v_row := COALESCE(v_new, v_old);

    CASE TG_TABLE_NAME
        WHEN 'memberships' THEN v_audited := TG_OP = 'INSERT'
            OR (v_old -> 'role', v_old -> 'scope_all_teams', v_old -> 'ended_at',
                v_old -> 'ended_by_user_id') IS DISTINCT FROM (v_new -> 'role', v_new -> 'scope_all_teams',
                                                               v_new -> 'ended_at', v_new -> 'ended_by_user_id');

        WHEN 'game_teams' THEN IF TG_OP = 'INSERT' THEN
            v_audited := true;
        ELSE
            v_reason_required := (v_old ->> 'stats_status') = 'VALIDATED';
            v_audited := v_reason_required
                OR (v_old -> 'score', v_old -> 'is_forfeiting', v_old -> 'stats_status',
                    v_old -> 'points_discrepancy_accepted') IS DISTINCT FROM (v_new -> 'score',
                                                                              v_new -> 'is_forfeiting',
                                                                              v_new -> 'stats_status',
                                                                              v_new -> 'points_discrepancy_accepted');
        END IF;

        WHEN 'game_participations' THEN SELECT gt.stats_status
                                        INTO v_parent_status
                                        FROM game_teams gt
                                        WHERE gt.id = (v_row ->> 'game_team_id')::uuid;

                                        v_audited := v_parent_status = 'VALIDATED';
                                        v_reason_required := v_audited;

        ELSE RAISE EXCEPTION 'audit_row_change() n''est pas prévue pour la table %', TG_TABLE_NAME;
        END CASE;

    IF NOT v_audited THEN
        RETURN NULL; -- trigger AFTER : la valeur de retour est ignorée
    END IF;

    IF v_reason_required AND v_reason IS NULL THEN
        RAISE EXCEPTION 'ARCWAY_CORRECTION_REASON_REQUIRED' USING ERRCODE = 'Z1001';
    END IF;

    INSERT INTO audit_log (organization_id, actor_user_id, entity_type, entity_id,
                           action, before_data, after_data, reason)
    VALUES ((v_row ->> 'organization_id')::uuid,
            app_user_id(),
            TG_TABLE_NAME,
            (v_row ->> 'id')::uuid,
            TG_OP,
            v_old,
            v_new,
            v_reason);

    RETURN NULL;
END;
$$;

-- -----------------------------------------------------------------------------
-- Triggers : la ligne est déjà écrite, une exception annule tout.
-- -----------------------------------------------------------------------------
CREATE TRIGGER trg_memberships_audit
    AFTER INSERT OR UPDATE
    ON memberships
    FOR EACH ROW
EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER trg_game_teams_audit
    AFTER INSERT OR UPDATE
    ON game_teams
    FOR EACH ROW
EXECUTE FUNCTION audit_row_change();

CREATE TRIGGER trg_game_participations_audit
    AFTER INSERT OR UPDATE OR DELETE
    ON game_participations
    FOR EACH ROW
EXECUTE FUNCTION audit_row_change();
