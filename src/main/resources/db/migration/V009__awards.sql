-- =============================================================================
-- V009 : palmarès
-- -----------------------------------------------------------------------------
-- On RÉVOQUE, on ne supprime jamais. team_id est un instantané : l'équipe du
-- joueur À LA DATE D'ATTRIBUTION.
-- Un seul bénéficiaire ACTIF par récompense et par saison : deux attributions
-- simultanées sont départagées par la base.
-- =============================================================================

CREATE TYPE award_kind AS ENUM ('MVP', 'BEST_DEFENDER', 'BEST_ROOKIE');

CREATE TABLE awards
(
    id                 uuid        NOT NULL DEFAULT gen_random_uuid(),
    organization_id    uuid        NOT NULL,
    season_id          uuid        NOT NULL,
    player_id          uuid        NOT NULL,
    kind               award_kind  NOT NULL,
    team_id            uuid,
    awarded_by_user_id uuid        NOT NULL,
    awarded_at         timestamptz NOT NULL,
    citation           text,
    revoked_at         timestamptz,
    revoked_by_user_id uuid,
    revoked_reason     text,
    created_at         timestamptz NOT NULL DEFAULT now(),
    updated_at         timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT pk_awards PRIMARY KEY (id),
    CONSTRAINT fk_awards_organization FOREIGN KEY (organization_id)
        REFERENCES organizations (id) ON DELETE RESTRICT,
    CONSTRAINT fk_awards_season FOREIGN KEY (season_id, organization_id)
        REFERENCES seasons (id, organization_id) ON DELETE RESTRICT,
    CONSTRAINT fk_awards_player FOREIGN KEY (player_id, organization_id)
        REFERENCES players (id, organization_id) ON DELETE RESTRICT,
    CONSTRAINT fk_awards_team FOREIGN KEY (team_id, organization_id)
        REFERENCES teams (id, organization_id) ON DELETE RESTRICT,
    CONSTRAINT fk_awards_awarded_by FOREIGN KEY (awarded_by_user_id)
        REFERENCES users (id) ON DELETE RESTRICT,
    CONSTRAINT fk_awards_revoked_by FOREIGN KEY (revoked_by_user_id)
        REFERENCES users (id) ON DELETE RESTRICT,
    -- Les trois colonnes de révocation sont renseignées ensemble, ou aucune.
    CONSTRAINT ck_awards_revocation CHECK (
        (revoked_at IS NULL) = (revoked_by_user_id IS NULL)
            AND (revoked_at IS NULL) = (revoked_reason IS NULL))
);

CREATE UNIQUE INDEX uq_awards_active_kind_season ON awards (season_id, kind)
    WHERE revoked_at IS NULL;
CREATE INDEX ix_awards_player ON awards (player_id);
CREATE INDEX ix_awards_org_season ON awards (organization_id, season_id);
