-- =============================================================================
-- V008 : feuille de match et statistiques d'un joueur
-- -----------------------------------------------------------------------------
-- Une ligne = un joueur sur la feuille d'une équipe pour un match.
-- Convention NULL : 0 = zéro constaté ; NULL = non suivi.
-- Un joueur n'est PAS obligé d'appartenir à l'effectif de l'équipe : le statut
-- « invité » est calculé, jamais stocké.
-- Pas de version propre : celle de game_teams protège la feuille entière.
-- Règles d'ensemble portées par l'application : au plus 5 titulaires, somme des
-- points = score, aucune ligne PENDING à la validation.
--
-- NB : les noms de contraintes de cette table utilisent le préfixe court
-- « participations ».
-- =============================================================================

CREATE TYPE participation_status AS ENUM ('PENDING', 'PLAYED', 'DNP');

CREATE TABLE game_participations
(
    id                 uuid                 NOT NULL DEFAULT gen_random_uuid(),
    organization_id    uuid                 NOT NULL,
    game_id            uuid                 NOT NULL, -- répété : un joueur n'apparaît qu'une fois par match
    game_team_id       uuid                 NOT NULL,
    player_id          uuid                 NOT NULL,
    status             participation_status NOT NULL DEFAULT 'PENDING',
    is_starter         boolean              NOT NULL DEFAULT false,
    jersey_number      smallint,
    seconds_played     integer,                       -- NULL = non suivi
    points             smallint             NOT NULL DEFAULT 0,
    offensive_rebounds smallint             NOT NULL DEFAULT 0,
    defensive_rebounds smallint             NOT NULL DEFAULT 0,
    reb_total          smallint GENERATED ALWAYS AS ((offensive_rebounds + defensive_rebounds)::smallint) STORED,
    assists            smallint             NOT NULL DEFAULT 0,
    steals             smallint             NOT NULL DEFAULT 0,
    blocks             smallint             NOT NULL DEFAULT 0,
    turnovers          smallint             NOT NULL DEFAULT 0,
    personal_fouls     smallint             NOT NULL DEFAULT 0,
    plus_minus         smallint,                      -- NULL = non suivi
    entered_by_user_id uuid                 NOT NULL,
    created_at         timestamptz          NOT NULL DEFAULT now(),
    updated_at         timestamptz          NOT NULL DEFAULT now(),

    CONSTRAINT pk_game_participations PRIMARY KEY (id),
    -- Un joueur ne joue pas deux fois dans un match.
    CONSTRAINT uq_participations_game_player UNIQUE (game_id, player_id),
    CONSTRAINT fk_participations_organization FOREIGN KEY (organization_id)
        REFERENCES organizations (id) ON DELETE RESTRICT,
    -- Garantit aussi la cohérence de game_id avec la feuille parente.
    CONSTRAINT fk_participations_game_team FOREIGN KEY (game_team_id, game_id, organization_id)
        REFERENCES game_teams (id, game_id, organization_id) ON DELETE RESTRICT,
    CONSTRAINT fk_participations_player FOREIGN KEY (player_id, organization_id)
        REFERENCES players (id, organization_id) ON DELETE RESTRICT,
    CONSTRAINT fk_participations_entered_by FOREIGN KEY (entered_by_user_id)
        REFERENCES users (id) ON DELETE RESTRICT,
    CONSTRAINT ck_participations_non_negative CHECK (
        points >= 0 AND offensive_rebounds >= 0 AND defensive_rebounds >= 0
            AND assists >= 0 AND steals >= 0 AND blocks >= 0
            AND turnovers >= 0 AND personal_fouls >= 0
            AND (seconds_played IS NULL OR seconds_played >= 0)),
    -- Plafond de plausibilité ; la limite réelle dépend du match.
    CONSTRAINT ck_participations_seconds_cap CHECK (seconds_played IS NULL OR seconds_played <= 7200),
    CONSTRAINT ck_participations_jersey CHECK (jersey_number IS NULL OR jersey_number BETWEEN 0 AND 99)
);

-- Un numéro de maillot est unique au sein de la feuille d'une équipe.
CREATE UNIQUE INDEX uq_participations_jersey ON game_participations (game_team_id, jersey_number)
    WHERE jersey_number IS NOT NULL;
CREATE INDEX ix_participations_game_team ON game_participations (game_team_id);
CREATE INDEX ix_participations_player ON game_participations (player_id);
