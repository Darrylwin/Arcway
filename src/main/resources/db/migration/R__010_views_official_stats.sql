-- =============================================================================
-- R__010 : vue contractuelle v_official_player_games
-- -----------------------------------------------------------------------------
-- SEULE source des analyses statistiques : une ligne par joueur et par match OFFICIEL.
--   Condition de ligne : participation PLAYED ET feuille VALIDATED ET match FINISHED.
--   Un match annulé sort donc de toutes les analyses ; une
--   feuille non validée n'y apparaît jamais.
--
-- security_invoker = true : la vue s'exécute avec les droits ET la RLS de l'appelant.
--
-- Contrat d'API : la formule de « efficiency » et la liste des colonnes en font partie.
-- Les modifier est un changement de contrat.
--
-- La vue est recréée par DROP puis CREATE : les droits sont perdus à chaque
-- recréation. Flyway ne rejoue R__030 que si SON contenu change : le GRANT est donc
-- répété ICI, juste après la création.
-- =============================================================================

DROP VIEW IF EXISTS v_official_player_games;

CREATE VIEW v_official_player_games
    WITH (security_invoker = true)
AS
SELECT gp.organization_id,
       gp.game_id,
       gp.game_team_id,
       gp.player_id,
       gt.team_id,
       g.competition_id,
       c.type                                                                                  AS competition_type,
       c.season_id,
       g.scheduled_at,
       p.first_name                                                                            AS player_first_name,
       p.last_name                                                                             AS player_last_name,
       p.playing_position,
       t.name                                                                                  AS team_name,
       gp.jersey_number,
       gp.is_starter,
       gp.seconds_played, -- NULL = non suivi
       gp.plus_minus,     -- NULL = non suivi
       gp.points,
       gp.offensive_rebounds,
       gp.defensive_rebounds,
       gp.reb_total,
       gp.assists,
       gp.steals,
       gp.blocks,
       gp.turnovers,
       gp.personal_fouls,
       -- Indice d'efficacité simplifié
       (gp.points + gp.reb_total + gp.assists + gp.steals + gp.blocks - gp.turnovers)::integer AS efficiency,
       -- Invité : le joueur n'est pas à l'effectif de l'équipe à la date du match,
       -- exprimée dans le fuseau de l'organisation.
       NOT EXISTS (SELECT 1
                   FROM roster_entries re
                   WHERE re.player_id = gp.player_id
                     AND re.team_id = gt.team_id
                     AND daterange(re.valid_from, re.valid_to, '[]')
                       @> (g.scheduled_at AT TIME ZONE o.timezone)::date)                      AS is_guest
FROM game_participations gp
         JOIN game_teams gt ON gt.id = gp.game_team_id AND gt.organization_id = gp.organization_id
         JOIN games g ON g.id = gp.game_id AND g.organization_id = gp.organization_id
         JOIN competitions c ON c.id = g.competition_id AND c.organization_id = g.organization_id
         JOIN players p ON p.id = gp.player_id AND p.organization_id = gp.organization_id
         JOIN teams t ON t.id = gt.team_id AND t.organization_id = gt.organization_id
         JOIN organizations o ON o.id = gp.organization_id
WHERE gp.status = 'PLAYED'
  AND gt.stats_status = 'VALIDATED'
  AND g.status = 'FINISHED';

GRANT SELECT ON v_official_player_games TO arcway_app;
