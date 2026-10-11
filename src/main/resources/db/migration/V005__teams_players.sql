-- =============================================================================
-- V005 : équipes, staff, joueurs, effectifs, invitations
-- -----------------------------------------------------------------------------
-- Toutes les FK vers un parent tenant sont COMPOSITES:
-- une ligne d'une organisation ne peut pas référencer l'identifiant d'une autre.
-- Les références optionnelles restent en MATCH SIMPLE : une
-- colonne NULL désactive la vérification, ce qui est voulu.
-- invitations est créée après players.
-- =============================================================================

CREATE TYPE staff_role AS ENUM ('HEAD_COACH', 'ASSISTANT_COACH', 'STATS_KEEPER', 'MANAGER');
CREATE TYPE basketball_position AS ENUM ('PG', 'SG', 'SF', 'PF', 'C');
CREATE TYPE invitation_status AS ENUM ('PENDING', 'ACCEPTED', 'REVOKED');

-- ---------------------------------------------------------------------
-- teams : une équipe externe est un adversaire non géré, sans feuille.
-- ---------------------------------------------------------------------
CREATE TABLE teams
(
    id              uuid        NOT NULL DEFAULT gen_random_uuid(),
    organization_id uuid        NOT NULL,
    name            text        NOT NULL,
    category        text, -- libre (« Senior », « U17 »)
    is_external     boolean     NOT NULL DEFAULT false,
    archived_at     timestamptz,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT pk_teams PRIMARY KEY (id),
    CONSTRAINT uq_teams_id_org UNIQUE (id, organization_id),
    CONSTRAINT fk_teams_organization FOREIGN KEY (organization_id)
        REFERENCES organizations (id) ON DELETE RESTRICT
);

-- Un nom d'équipe est unique parmi les équipes ACTIVES, sans tenir compte de la casse.
CREATE UNIQUE INDEX uq_teams_org_name_active ON teams (organization_id, lower(name))
    WHERE archived_at IS NULL;
CREATE INDEX ix_teams_org_active ON teams (organization_id) WHERE archived_at IS NULL;

-- -----------------------------------------------------------------------------
-- team_staff : équipes sur lesquelles un membre agit.
-- État courant : retirer un membre d'une équipe supprime la ligne.
-- -----------------------------------------------------------------------------
CREATE TABLE team_staff
(
    organization_id uuid        NOT NULL,
    team_id         uuid        NOT NULL,
    membership_id   uuid        NOT NULL,
    staff_role      staff_role  NOT NULL,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT pk_team_staff PRIMARY KEY (team_id, membership_id),
    CONSTRAINT fk_team_staff_organization FOREIGN KEY (organization_id)
        REFERENCES organizations (id) ON DELETE RESTRICT,
    CONSTRAINT fk_team_staff_team FOREIGN KEY (team_id, organization_id)
        REFERENCES teams (id, organization_id) ON DELETE RESTRICT,
    CONSTRAINT fk_team_staff_membership FOREIGN KEY (membership_id, organization_id)
        REFERENCES memberships (id, organization_id) ON DELETE RESTRICT
);

CREATE INDEX ix_team_staff_membership ON team_staff (membership_id);

-- -----------------------------------------------------------------------------
-- players : pas de team_id.
-- birth_date est une donnée sensible. Anonymisation : anonymized_at,
-- noms neutres, birth_date et user_id à NULL ; statistiques et récompenses conservées.
-- -----------------------------------------------------------------------------
CREATE TABLE players
(
    id               uuid        NOT NULL DEFAULT gen_random_uuid(),
    organization_id  uuid        NOT NULL,
    user_id          uuid, -- compte rattaché
    first_name       text        NOT NULL,
    last_name        text        NOT NULL,
    birth_date       date,
    height_cm        smallint,
    playing_position basketball_position,
    archived_at      timestamptz,
    anonymized_at    timestamptz,
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT pk_players PRIMARY KEY (id),
    CONSTRAINT uq_players_id_org UNIQUE (id, organization_id),
    CONSTRAINT fk_players_organization FOREIGN KEY (organization_id)
        REFERENCES organizations (id) ON DELETE RESTRICT,
    CONSTRAINT fk_players_user FOREIGN KEY (user_id)
        REFERENCES users (id) ON DELETE RESTRICT,
    CONSTRAINT ck_players_height CHECK (height_cm IS NULL OR height_cm BETWEEN 100 AND 260),
    CONSTRAINT ck_players_anonymized CHECK (anonymized_at IS NULL OR (birth_date IS NULL AND user_id IS NULL))
);

-- Un compte ne peut être rattaché qu'à un seul joueur par organisation.
CREATE UNIQUE INDEX uq_players_org_user ON players (organization_id, user_id)
    WHERE user_id IS NOT NULL;
-- Blocage dur des doublons certains.
CREATE UNIQUE INDEX uq_players_org_name_birth
    ON players (organization_id, lower(first_name), lower(last_name), birth_date)
    WHERE birth_date IS NOT NULL;
CREATE INDEX ix_players_org_name ON players (organization_id, last_name, first_name);

-- -----------------------------------------------------------------------------
-- roster_entries : historique des appartenances joueur / équipe.
-- Pas de version : l'exclusion garantit la cohérence, y compris en concurrence.
-- Un joueur peut appartenir à deux équipes différentes en même temps.
-- -----------------------------------------------------------------------------
CREATE TABLE roster_entries
(
    id                    uuid        NOT NULL DEFAULT gen_random_uuid(),
    organization_id       uuid        NOT NULL,
    team_id               uuid        NOT NULL,
    player_id             uuid        NOT NULL,
    valid_from            date        NOT NULL,
    valid_to              date,     -- NULL = toujours dans l'équipe
    default_jersey_number smallint, -- pré-remplit la feuille de match
    created_at            timestamptz NOT NULL DEFAULT now(),
    updated_at            timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT pk_roster_entries PRIMARY KEY (id),
    CONSTRAINT fk_roster_entries_organization FOREIGN KEY (organization_id)
        REFERENCES organizations (id) ON DELETE RESTRICT,
    CONSTRAINT fk_roster_entries_team FOREIGN KEY (team_id, organization_id)
        REFERENCES teams (id, organization_id) ON DELETE RESTRICT,
    CONSTRAINT fk_roster_entries_player FOREIGN KEY (player_id, organization_id)
        REFERENCES players (id, organization_id) ON DELETE RESTRICT,
    CONSTRAINT ck_roster_entries_period CHECK (valid_to IS NULL OR valid_to >= valid_from),
    CONSTRAINT ck_roster_entries_jersey CHECK (default_jersey_number IS NULL
        OR default_jersey_number BETWEEN 0 AND 99),
    -- Même joueur, même équipe, périodes qui se chevauchent : refusé (SQLSTATE 23P01).
    CONSTRAINT ex_roster_entries_no_overlap EXCLUDE USING gist (
        player_id WITH =,
        team_id WITH =,
        daterange(valid_from, valid_to, '[]') WITH &&
        )
);

CREATE INDEX ix_roster_entries_team_open ON roster_entries (team_id) WHERE valid_to IS NULL;
CREATE INDEX ix_roster_entries_player_from ON roster_entries (player_id, valid_from DESC);

-- -----------------------------------------------------------------------------
-- invitations
-- Jeton : <organization_id>.<secret> ; seul le SHA-256 du jeton complet est stocké.
-- L'expiration est DÉRIVÉE (PENDING et expires_at < now()), jamais stockée.
-- Acceptation atomique : UPDATE ... WHERE status = 'PENDING' AND expires_at > now().
-- -----------------------------------------------------------------------------
CREATE TABLE invitations
(
    id                       uuid              NOT NULL DEFAULT gen_random_uuid(),
    organization_id          uuid              NOT NULL,
    invitee_email            citext            NOT NULL,
    role                     org_role          NOT NULL,
    scope_all_teams          boolean           NOT NULL DEFAULT false,
    player_id                uuid, -- profil joueur à rattacher à l'acceptation
    token_hash               bytea             NOT NULL,
    status                   invitation_status NOT NULL DEFAULT 'PENDING',
    invited_by_membership_id uuid              NOT NULL,
    expires_at               timestamptz       NOT NULL,
    accepted_by_user_id      uuid,
    accepted_at              timestamptz,
    created_at               timestamptz       NOT NULL DEFAULT now(),
    updated_at               timestamptz       NOT NULL DEFAULT now(),

    CONSTRAINT pk_invitations PRIMARY KEY (id),
    CONSTRAINT uq_invitations_token_hash UNIQUE (token_hash),
    CONSTRAINT fk_invitations_organization FOREIGN KEY (organization_id)
        REFERENCES organizations (id) ON DELETE RESTRICT,
    CONSTRAINT fk_invitations_player FOREIGN KEY (player_id, organization_id)
        REFERENCES players (id, organization_id) ON DELETE RESTRICT,
    CONSTRAINT fk_invitations_invited_by FOREIGN KEY (invited_by_membership_id, organization_id)
        REFERENCES memberships (id, organization_id) ON DELETE RESTRICT,
    CONSTRAINT fk_invitations_accepted_by FOREIGN KEY (accepted_by_user_id)
        REFERENCES users (id) ON DELETE RESTRICT,
    CONSTRAINT ck_invitations_scope_analyst_only CHECK (role = 'ANALYST' OR scope_all_teams = false),
    CONSTRAINT ck_invitations_accepted
        CHECK ((status = 'ACCEPTED') = (accepted_at IS NOT NULL AND accepted_by_user_id IS NOT NULL))
);

-- Une seule invitation en attente par adresse et par organisation.
CREATE UNIQUE INDEX uq_invitations_pending_email ON invitations (organization_id, invitee_email)
    WHERE status = 'PENDING';
CREATE INDEX ix_invitations_org_status ON invitations (organization_id, status);
