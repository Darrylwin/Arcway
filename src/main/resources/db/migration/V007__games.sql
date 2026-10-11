-- =============================================================================
-- V007 : matchs et équipes d'un match
-- -----------------------------------------------------------------------------
-- Un match n'est jamais supprimé : CANCELLED est terminal, un match de
-- remplacement référence l'annulé par replaces_game_id.
-- Le vainqueur n'est pas stocké : il se déduit des scores.
-- Les transitions d'état et le fait qu'un match ait EXACTEMENT deux équipes sont
-- des règles applicatives ; la base garantit « au plus deux ».
-- =============================================================================

CREATE TYPE game_status AS ENUM ('SCHEDULED', 'IN_PROGRESS', 'FINISHED', 'POSTPONED', 'CANCELLED');
CREATE TYPE game_side AS ENUM ('HOME', 'AWAY');
CREATE TYPE stats_status AS ENUM ('NOT_TRACKED', 'DRAFT', 'SUBMITTED', 'VALIDATED');

-- -------------------------------------------
-- games
-- -------------------------------------------
CREATE TABLE games
(
    id               uuid        NOT NULL DEFAULT gen_random_uuid(),
    organization_id  uuid        NOT NULL,
    competition_id   uuid        NOT NULL,
    scheduled_at     timestamptz,
    venue_name       text,                                 -- lieu en texte libre
    status           game_status NOT NULL DEFAULT 'SCHEDULED',
    status_reason    text,
    round_label      text,
    replaces_game_id uuid,                                 -- match rejoué après annulation ou abandon
    version          bigint      NOT NULL DEFAULT 0,
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT pk_games PRIMARY KEY (id),
    CONSTRAINT uq_games_id_org UNIQUE (id, organization_id),
    CONSTRAINT fk_games_organization FOREIGN KEY (organization_id)
        REFERENCES organizations (id) ON DELETE RESTRICT,
    CONSTRAINT fk_games_competition FOREIGN KEY (competition_id, organization_id)
        REFERENCES competitions (id, organization_id) ON DELETE RESTRICT,
    CONSTRAINT fk_games_replaces FOREIGN KEY (replaces_game_id, organization_id)
        REFERENCES games (id, organization_id) ON DELETE RESTRICT,
    CONSTRAINT ck_games_scheduled_required
        CHECK (status NOT IN ('SCHEDULED', 'IN_PROGRESS', 'FINISHED') OR scheduled_at IS NOT NULL),
    CONSTRAINT ck_games_reason_required
        CHECK (status NOT IN ('POSTPONED', 'CANCELLED') OR status_reason IS NOT NULL),
    CONSTRAINT ck_games_replaces_not_self CHECK (replaces_game_id IS NULL OR replaces_game_id <> id)
);

CREATE INDEX ix_games_competition_time ON games (competition_id, scheduled_at);
CREATE INDEX ix_games_org_time ON games (organization_id, scheduled_at);

-- -----------------------------------------------------------------------------
-- game_teams : une ligne par équipe et par match.
-- Chaque équipe a sa propre feuille et son propre cycle.
-- version : protège le score, le forfait ET la feuille entière :
-- toute modification d'une ligne de feuille incrémente de force cette version.
-- =============================================================================
CREATE TABLE game_teams
(
    id                           uuid         NOT NULL DEFAULT gen_random_uuid(),
    organization_id              uuid         NOT NULL,
    game_id                      uuid         NOT NULL,
    team_id                      uuid         NOT NULL,
    side                         game_side    NOT NULL,
    score                        smallint,                  -- NULL tant que le match n'est pas terminé
    is_forfeiting                boolean      NOT NULL DEFAULT false,
    stats_status                 stats_status NOT NULL DEFAULT 'NOT_TRACKED',
    points_discrepancy_accepted  boolean      NOT NULL DEFAULT false,   -- dérogation ADMIN
    submitted_at                 timestamptz,
    validated_at                 timestamptz,
    submitted_by_user_id         uuid,
    validated_by_user_id         uuid,
    version                      bigint       NOT NULL DEFAULT 0,
    created_at                   timestamptz  NOT NULL DEFAULT now(),
    updated_at                   timestamptz  NOT NULL DEFAULT now(),

    CONSTRAINT pk_game_teams PRIMARY KEY (id),
    CONSTRAINT uq_game_teams_game_side UNIQUE (game_id, side),
    CONSTRAINT uq_game_teams_game_team UNIQUE (game_id, team_id),
    CONSTRAINT uq_game_teams_id_game_org UNIQUE (id, game_id, organization_id),   -- cible de la FK des feuilles
    CONSTRAINT fk_game_teams_organization FOREIGN KEY (organization_id)
        REFERENCES organizations (id) ON DELETE RESTRICT,
    CONSTRAINT fk_game_teams_game FOREIGN KEY (game_id, organization_id)
        REFERENCES games (id, organization_id) ON DELETE RESTRICT,
    CONSTRAINT fk_game_teams_team FOREIGN KEY (team_id, organization_id)
        REFERENCES teams (id, organization_id) ON DELETE RESTRICT,
    CONSTRAINT fk_game_teams_submitted_by FOREIGN KEY (submitted_by_user_id)
        REFERENCES users (id) ON DELETE RESTRICT,
    CONSTRAINT fk_game_teams_validated_by FOREIGN KEY (validated_by_user_id)
        REFERENCES users (id) ON DELETE RESTRICT,
    CONSTRAINT ck_game_teams_score CHECK (score IS NULL OR score >= 0),
    CONSTRAINT ck_game_teams_validated
        CHECK ((stats_status = 'VALIDATED') = (validated_at IS NOT NULL AND validated_by_user_id IS NOT NULL)),
    CONSTRAINT ck_game_teams_submitted CHECK (stats_status <> 'SUBMITTED' OR submitted_at IS NOT NULL)
);

-- Au plus une équipe forfaitaire par match.
CREATE UNIQUE INDEX uq_game_teams_one_forfeit ON game_teams (game_id) WHERE is_forfeiting;
CREATE INDEX ix_game_teams_team_game ON game_teams (team_id, game_id);
CREATE INDEX ix_game_teams_stats_queue ON game_teams (organization_id, stats_status)
    WHERE stats_status IN ('DRAFT', 'SUBMITTED');
