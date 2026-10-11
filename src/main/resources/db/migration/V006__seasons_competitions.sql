-- =============================================================================
-- V006 : cadre temporel
-- -----------------------------------------------------------------------------
-- Pas de contrainte de non-chevauchement entre saisons. La saison d'un match
-- se déduit de sa compétition ; un match amical appartient à une compétition de
-- type FRIENDLY.
-- =============================================================================

CREATE TYPE season_status AS ENUM ('PLANNED', 'ACTIVE', 'CLOSED');
CREATE TYPE competition_type AS ENUM ('LEAGUE', 'CUP', 'TOURNAMENT', 'FRIENDLY');
CREATE TYPE competition_status AS ENUM ('DRAFT', 'ACTIVE', 'COMPLETED', 'CANCELLED');

-- -------------------------------------------------
-- seasons
-- -------------------------------------------------
CREATE TABLE seasons
(
    id              uuid          NOT NULL DEFAULT gen_random_uuid(),
    organization_id uuid          NOT NULL,
    name            text          NOT NULL,
    start_date      date          NOT NULL,
    end_date        date          NOT NULL,
    status          season_status NOT NULL DEFAULT 'PLANNED',
    closed_at       timestamptz,
    created_at      timestamptz   NOT NULL DEFAULT now(),
    updated_at      timestamptz   NOT NULL DEFAULT now(),

    CONSTRAINT pk_seasons PRIMARY KEY (id),
    CONSTRAINT uq_seasons_id_org UNIQUE (id, organization_id),
    CONSTRAINT uq_seasons_org_name UNIQUE (organization_id, name),
    CONSTRAINT fk_seasons_organization FOREIGN KEY (organization_id)
        REFERENCES organizations (id) ON DELETE RESTRICT,
    CONSTRAINT ck_seasons_dates CHECK (end_date > start_date),
    -- Une réouverture remet closed_at à NULL.
    CONSTRAINT ck_seasons_closed CHECK ((status = 'CLOSED') = (closed_at IS NOT NULL))
);

CREATE INDEX ix_seasons_org_start ON seasons (organization_id, start_date DESC);

-- -------------------------------------------------
-- competitions
-- -------------------------------------------------
CREATE TABLE competitions
(
    id              uuid               NOT NULL DEFAULT gen_random_uuid(),
    organization_id uuid               NOT NULL,
    season_id       uuid               NOT NULL,
    name            text               NOT NULL,
    type            competition_type   NOT NULL,
    status          competition_status NOT NULL DEFAULT 'DRAFT',
    start_date      date,
    end_date        date,
    created_at      timestamptz        NOT NULL DEFAULT now(),
    updated_at      timestamptz        NOT NULL DEFAULT now(),

    CONSTRAINT pk_competitions PRIMARY KEY (id),
    CONSTRAINT uq_competitions_id_org UNIQUE (id, organization_id),
    CONSTRAINT uq_competitions_season_name UNIQUE (season_id, name),
    CONSTRAINT fk_competitions_organization FOREIGN KEY (organization_id)
        REFERENCES organizations (id) ON DELETE RESTRICT,
    CONSTRAINT fk_competitions_season FOREIGN KEY (season_id, organization_id)
        REFERENCES seasons (id, organization_id) ON DELETE RESTRICT,
    CONSTRAINT ck_competitions_dates CHECK (start_date IS NULL OR end_date IS NULL OR end_date >= start_date)
);

CREATE INDEX ix_competitions_season_status ON competitions (season_id, status);

-- -------------------------------------------------
-- competition_teams
-- -------------------------------------------------
CREATE TABLE competition_teams
(
    organization_id uuid        NOT NULL,
    competition_id  uuid        NOT NULL,
    team_id         uuid        NOT NULL,
    registered_at   timestamptz NOT NULL DEFAULT now(),
    withdrawn_at    timestamptz,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT pk_competition_teams PRIMARY KEY (competition_id, team_id),
    CONSTRAINT fk_competition_teams_organization FOREIGN KEY (organization_id)
        REFERENCES organizations (id) ON DELETE RESTRICT,
    CONSTRAINT fk_competition_teams_competition FOREIGN KEY (competition_id, organization_id)
        REFERENCES competitions (id, organization_id) ON DELETE RESTRICT,
    CONSTRAINT fk_competition_teams_team FOREIGN KEY (team_id, organization_id)
        REFERENCES teams (id, organization_id) ON DELETE RESTRICT,
    CONSTRAINT ck_competition_teams_withdrawn CHECK (withdrawn_at IS NULL OR withdrawn_at >= registered_at)
);

CREATE INDEX ix_competition_teams_team ON competition_teams (team_id);
