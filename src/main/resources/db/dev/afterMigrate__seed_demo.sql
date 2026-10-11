-- =============================================================================
-- Arcway : données de DÉMONSTRATION
-- -----------------------------------------------------------------------------
-- Chargé UNIQUEMENT par le profil « local » (spring.flyway.locations inclut
-- classpath:db/dev). Jamais présent en production : application-prod et
-- application-migrate ne listent que classpath:db/migration.
--
-- Exécution : callback Flyway « afterMigrate », après CHAQUE migration, avec le
-- rôle arcway_migrator (propriétaire : la RLS n'est pas appliquée à ce script).
-- IDEMPOTENT : rejouable sans doublon ni erreur (identifiants déterministes +
-- ON CONFLICT DO NOTHING).
--
-- COMPTES (mot de passe commun : Arcway-Demo-2026!)
--   awa.koffi@arcway.test     Lions de Lomé : ADMIN         | Eagles Academy : VIEWER
--   kossi.mensah@arcway.test  Lions de Lomé : ANALYST, équipe « Lions Seniors » seulement
--   esso.kpetsu@arcway.test   Lions de Lomé : ANALYST, toutes les équipes
--   ama.dossou@arcway.test    Lions de Lomé : VIEWER
--   yao.agbeko@arcway.test    Eagles Academy : ADMIN
--
-- ORGANISATIONS
--   lions-lome      (Africa/Lome)    : jeu de données riche pour les statistiques
--   eagles-academy  (Africa/Abidjan) : petit jeu distinct, pour tester l'isolation
--
-- CAS COUVERTS (Lions de Lomé)
--   - 3 matchs terminés à feuille VALIDÉE   -> comptent dans les statistiques
--   - 1 match terminé à feuille BROUILLON   -> exclu des statistiques
--   - 1 match ANNULÉ, remplacé par 1 match PLANIFIÉ (replaces_game_id)
--   - 1 joueur INVITÉ (U17 sur la feuille des seniors, match du 3 octobre)
--   - 1 joueur U17 qui n'a aucune statistique
--   - saison 2025-2026 CLOSE avec 2 récompenses ; saison 2026-2027 ACTIVE
--   - valeurs « non suivies » (NULL) : +/- du match du 3 octobre, temps des absents
-- =============================================================================

-- Identifiant déterministe à partir d'une clé lisible : mêmes UUID à chaque rejeu.
CREATE OR REPLACE FUNCTION pg_temp.sid(key text) RETURNS uuid
    LANGUAGE sql
    IMMUTABLE
AS
$$
SELECT md5('arcway-seed:' || key)::uuid
$$;

-- -----------------------------------------------------------------------------
-- 1. Utilisateurs (tables globales)
--    password_hash : Argon2id (m=16384, t=2, p=1) de « Arcway-Demo-2026! ».
--    Ce hash est PUBLIC et ne sert qu'aux comptes de démonstration locaux.
-- -----------------------------------------------------------------------------
INSERT INTO users (id, email, password_hash, first_name, last_name, locale, email_verified_at)
SELECT pg_temp.sid('user:' || v.key),
       v.email,
       '$argon2id$v=19$m=16384,t=2,p=1$CPr6wkcYLaixg12UA7pwyQ$wgjVDgBtfjmWYzkaZYg2HzrJ+76o6b/0wBIfxF5eniU',
       v.first_name,
       v.last_name,
       'fr',
       now()
FROM (VALUES ('awa', 'awa.koffi@arcway.test', 'Awa', 'Koffi'),
             ('kossi', 'kossi.mensah@arcway.test', 'Kossi', 'Mensah'),
             ('esso', 'esso.kpetsu@arcway.test', 'Esso', 'Kpetsu'),
             ('ama', 'ama.dossou@arcway.test', 'Ama', 'Dossou'),
             ('yao', 'yao.agbeko@arcway.test', 'Yao', 'Agbeko')) AS v(key, email, first_name, last_name)
ON CONFLICT DO NOTHING;

-- -----------------------------------------------------------------------------
-- 2. Organisations
-- -----------------------------------------------------------------------------
INSERT INTO organizations (id, name, slug, timezone, created_by_user_id)
VALUES (pg_temp.sid('org:lions'), 'Lions de Lomé', 'lions-lome', 'Africa/Lome', pg_temp.sid('user:awa')),
       (pg_temp.sid('org:eagles'), 'Eagles Academy', 'eagles-academy', 'Africa/Abidjan', pg_temp.sid('user:yao'))
ON CONFLICT DO NOTHING;

-- -----------------------------------------------------------------------------
-- 3. Appartenances (le trigger d'audit trace les insertions)
-- -----------------------------------------------------------------------------
INSERT INTO memberships (id, organization_id, user_id, role, scope_all_teams)
SELECT pg_temp.sid('membership:' || v.org || ':' || v.usr),
       pg_temp.sid('org:' || v.org),
       pg_temp.sid('user:' || v.usr),
       v.role::org_role,
       v.scope_all
FROM (VALUES ('lions', 'awa', 'ADMIN', false),
             ('lions', 'kossi', 'ANALYST', false),
             ('lions', 'esso', 'ANALYST', true),
             ('lions', 'ama', 'VIEWER', false),
             ('eagles', 'yao', 'ADMIN', false),
             ('eagles', 'awa', 'VIEWER', false)) AS v(org, usr, role, scope_all)
ON CONFLICT DO NOTHING;

-- -----------------------------------------------------------------------------
-- 4. Équipes (« external » : adversaire non géré, sans feuille de statistiques)
-- -----------------------------------------------------------------------------
INSERT INTO teams (id, organization_id, name, category, is_external)
SELECT pg_temp.sid('team:' || v.org || ':' || v.key),
       pg_temp.sid('org:' || v.org),
       v.name,
       v.category,
       v.is_external
FROM (VALUES ('lions', 'seniors', 'Lions Seniors', 'Senior', false),
             ('lions', 'u17', 'Lions U17', 'U17', false),
             ('lions', 'kara', 'Kara Hoops', 'Senior', true),
             ('lions', 'sokode', 'Sokodé Titans', 'Senior', true),
             ('eagles', 'a', 'Eagles A', 'Senior', false),
             ('eagles', 'rivals', 'Rivals BC', 'Senior', true)) AS v(org, key, name, category, is_external)
ON CONFLICT DO NOTHING;

-- Périmètre : Kossi n'agit que sur les Seniors (scope_all_teams = false).
-- Esso (scope_all_teams = true) n'a besoin d'aucune ligne ; Awa est ADMIN.
INSERT INTO team_staff (organization_id, team_id, membership_id, staff_role)
VALUES (pg_temp.sid('org:lions'),
        pg_temp.sid('team:lions:seniors'),
        pg_temp.sid('membership:lions:kossi'),
        'STATS_KEEPER')
ON CONFLICT DO NOTHING;

-- -----------------------------------------------------------------------------
-- 5. Joueurs et effectifs
-- -----------------------------------------------------------------------------
INSERT INTO players (id, organization_id, first_name, last_name, birth_date, height_cm, playing_position)
SELECT pg_temp.sid('player:' || v.org || ':' || v.key),
       pg_temp.sid('org:' || v.org),
       v.first_name,
       v.last_name,
       v.birth_date::date,
       v.height,
       v.position::basketball_position
FROM (VALUES
          -- Lions : seniors
          ('lions', 'p1', 'Kofi', 'Adjovi', '1998-03-14', 183, 'PG'),
          ('lions', 'p2', 'Yaovi', 'Tchalla', '1999-07-02', 188, 'SG'),
          ('lions', 'p3', 'Edem', 'Amouzou', '2000-11-21', 193, 'SF'),
          ('lions', 'p4', 'Komlan', 'Dzogbe', '1997-05-09', 201, 'PF'),
          ('lions', 'p5', 'Mawuli', 'Sodji', '1996-01-30', 208, 'C'),
          ('lions', 'p6', 'Senam', 'Akakpo', '2001-09-17', 180, 'PG'),
          ('lions', 'p7', 'Dodzi', 'Lawson', '2002-02-11', 186, 'SG'),
          ('lions', 'p8', 'Jean-Marc', 'Atsou', '1999-12-05', 191, 'SF'),
          ('lions', 'p9', 'Ayaovi', 'Kpodar', '2000-06-25', 198, 'PF'),
          -- Lions : U17 (mineurs : date de naissance sensible)
          ('lions', 'p10', 'Elom', 'Ahlin', '2010-04-03', 185, 'SF'),
          ('lions', 'p11', 'Mawuna', 'Houngbo', '2010-08-19', 175, 'PG'),
          ('lions', 'p12', 'Kodjo', 'Bakai', '2009-12-01', 196, 'C'),
          -- Eagles
          ('eagles', 'e1', 'Kokou', 'Adom', '1999-01-15', 182, 'PG'),
          ('eagles', 'e2', 'Abalo', 'Tchagbele', '1998-06-20', 187, 'SG'),
          ('eagles', 'e3', 'Essi', 'Folly', '2000-03-08', 192, 'SF'),
          ('eagles', 'e4', 'Komi', 'Gaglo', '1997-10-27', 200, 'PF'),
          ('eagles', 'e5', 'Yawo', 'Agbodjan', '1996-08-12', 206,
           'C')) AS v(org, key, first_name, last_name, birth_date, height, position)
ON CONFLICT DO NOTHING;

-- Effectifs : p10 est à l'effectif des U17 UNIQUEMENT (il sera « invité » chez les seniors).
INSERT INTO roster_entries (id, organization_id, team_id, player_id, valid_from, default_jersey_number)
SELECT pg_temp.sid('roster:' || v.org || ':' || v.player || ':' || v.team),
       pg_temp.sid('org:' || v.org),
       pg_temp.sid('team:' || v.org || ':' || v.team),
       pg_temp.sid('player:' || v.org || ':' || v.player),
       v.valid_from::date,
       v.jersey
FROM (VALUES ('lions', 'p1', 'seniors', '2026-08-15', 4),
             ('lions', 'p2', 'seniors', '2026-08-15', 7),
             ('lions', 'p3', 'seniors', '2026-08-15', 11),
             ('lions', 'p4', 'seniors', '2026-08-15', 14),
             ('lions', 'p5', 'seniors', '2026-08-15', 23),
             ('lions', 'p6', 'seniors', '2026-08-15', 5),
             ('lions', 'p7', 'seniors', '2026-08-15', 9),
             ('lions', 'p8', 'seniors', '2026-08-15', 10),
             ('lions', 'p9', 'seniors', '2026-08-15', 15),
             ('lions', 'p10', 'u17', '2026-09-01', 8),
             ('lions', 'p11', 'u17', '2026-09-01', 3),
             ('lions', 'p12', 'u17', '2026-09-01', 12),
             ('eagles', 'e1', 'a', '2026-08-20', 4),
             ('eagles', 'e2', 'a', '2026-08-20', 7),
             ('eagles', 'e3', 'a', '2026-08-20', 11),
             ('eagles', 'e4', 'a', '2026-08-20', 14),
             ('eagles', 'e5', 'a', '2026-08-20', 23)) AS v(org, player, team, valid_from, jersey)
ON CONFLICT DO NOTHING;

-- -----------------------------------------------------------------------------
-- 6. Saisons, compétitions, inscriptions
-- -----------------------------------------------------------------------------
INSERT INTO seasons (id, organization_id, name, start_date, end_date, status, closed_at)
SELECT pg_temp.sid('season:' || v.org || ':' || v.key),
       pg_temp.sid('org:' || v.org),
       v.name,
       v.start_date::date,
       v.end_date::date,
       v.status::season_status,
       v.closed_at::timestamptz
FROM (VALUES ('lions', '2025', '2025-2026', '2025-09-01', '2026-06-30', 'CLOSED', '2026-07-01 08:00:00+00'),
             ('lions', '2026', '2026-2027', '2026-09-01', '2027-06-30', 'ACTIVE', NULL),
             ('eagles', '2026', '2026-2027', '2026-09-01', '2027-06-30', 'ACTIVE', NULL))
         AS v(org, key, name, start_date, end_date, status, closed_at)
ON CONFLICT DO NOTHING;

INSERT INTO competitions (id, organization_id, season_id, name, type, status, start_date, end_date)
SELECT pg_temp.sid('competition:' || v.org || ':' || v.key),
       pg_temp.sid('org:' || v.org),
       pg_temp.sid('season:' || v.org || ':' || v.season),
       v.name,
       v.type::competition_type,
       'ACTIVE'::competition_status,
       v.start_date::date,
       v.end_date::date
FROM (VALUES ('lions', 'league', '2026', 'Championnat National', 'LEAGUE', '2026-09-05', '2027-05-30'),
             ('eagles', 'cup', '2026', 'Coupe Régionale', 'CUP', '2026-09-10', '2027-03-31'))
         AS v(org, key, season, name, type, start_date, end_date)
ON CONFLICT DO NOTHING;

-- Une compétition ACTIVE exige au moins 2 équipes inscrites (règle applicative).
INSERT INTO competition_teams (organization_id, competition_id, team_id)
SELECT pg_temp.sid('org:' || v.org),
       pg_temp.sid('competition:' || v.org || ':' || v.competition),
       pg_temp.sid('team:' || v.org || ':' || v.team)
FROM (VALUES ('lions', 'league', 'seniors'),
             ('lions', 'league', 'kara'),
             ('lions', 'league', 'sokode'),
             ('eagles', 'cup', 'a'),
             ('eagles', 'cup', 'rivals')) AS v(org, competition, team)
ON CONFLICT DO NOTHING;

-- -----------------------------------------------------------------------------
-- 7. Matchs
--    g1, g2, g3 : terminés, feuille des Lions VALIDÉE (statistiques officielles)
--    g4         : terminé, feuille en BROUILLON (exclu des statistiques)
--    g6         : ANNULÉ ; g5 le REMPLACE (replaces_game_id), planifié
--    Les instants sont en UTC ; Africa/Lome est UTC+0.
-- -----------------------------------------------------------------------------
INSERT INTO games (id, organization_id, competition_id, scheduled_at, venue_name,
                   status, status_reason, round_label)
SELECT pg_temp.sid('game:' || v.org || ':' || v.key),
       pg_temp.sid('org:' || v.org),
       pg_temp.sid('competition:' || v.org || ':' || v.competition),
       v.scheduled_at::timestamptz,
       v.venue,
       v.status::game_status,
       v.status_reason,
       v.round_label
FROM (VALUES ('lions', 'g1', 'league', '2026-09-12 18:00:00+00', 'Palais des Sports de Lomé', 'FINISHED', NULL,
              'Journée 1'),
             ('lions', 'g2', 'league', '2026-09-26 17:00:00+00', 'Complexe de Sokodé', 'FINISHED', NULL, 'Journée 3'),
             ('lions', 'g3', 'league', '2026-10-03 18:00:00+00', 'Palais des Sports de Lomé', 'FINISHED', NULL,
              'Journée 4'),
             ('lions', 'g4', 'league', '2026-10-10 18:00:00+00', 'Palais des Sports de Lomé', 'FINISHED', NULL,
              'Journée 5'),
             ('lions', 'g6', 'league', '2026-10-17 18:00:00+00', 'Palais des Sports de Lomé', 'CANCELLED',
              'Salle indisponible', 'Journée 6'),
             ('eagles', 'g1', 'cup', '2026-09-20 16:00:00+00', 'Gymnase Eagles', 'FINISHED', NULL, 'Huitièmes'))
         AS v(org, key, competition, scheduled_at, venue, status, status_reason, round_label)
ON CONFLICT DO NOTHING;

-- Match de remplacement (inséré après l'annulé qu'il référence).
INSERT INTO games (id, organization_id, competition_id, scheduled_at, venue_name,
                   status, round_label, replaces_game_id)
VALUES (pg_temp.sid('game:lions:g5'),
        pg_temp.sid('org:lions'),
        pg_temp.sid('competition:lions:league'),
        '2026-10-31 18:00:00+00',
        'Palais des Sports de Lomé',
        'SCHEDULED',
        'Journée 6 (reportée)',
        pg_temp.sid('game:lions:g6'))
ON CONFLICT DO NOTHING;

-- Équipes des matchs. Les feuilles à valider naissent en DRAFT : la validation
-- (étape 9) passe ensuite par une mise à jour, comme dans l'application.
-- Les équipes externes restent NOT_TRACKED (pas de feuille).
INSERT INTO game_teams (id, organization_id, game_id, team_id, side, score, stats_status)
SELECT pg_temp.sid('gt:' || v.org || ':' || v.game || ':' || v.team),
       pg_temp.sid('org:' || v.org),
       pg_temp.sid('game:' || v.org || ':' || v.game),
       pg_temp.sid('team:' || v.org || ':' || v.team),
       v.side::game_side,
       v.score,
       v.stats_status::stats_status
FROM (VALUES ('lions', 'g1', 'seniors', 'HOME', 84, 'DRAFT'),
             ('lions', 'g1', 'kara', 'AWAY', 76, 'NOT_TRACKED'),
             ('lions', 'g2', 'sokode', 'HOME', 71, 'NOT_TRACKED'),
             ('lions', 'g2', 'seniors', 'AWAY', 79, 'DRAFT'),
             ('lions', 'g3', 'seniors', 'HOME', 68, 'DRAFT'),
             ('lions', 'g3', 'kara', 'AWAY', 72, 'NOT_TRACKED'),
             ('lions', 'g4', 'seniors', 'HOME', 90, 'DRAFT'),
             ('lions', 'g4', 'sokode', 'AWAY', 85, 'NOT_TRACKED'),
             ('lions', 'g5', 'seniors', 'HOME', NULL, 'NOT_TRACKED'),
             ('lions', 'g5', 'kara', 'AWAY', NULL, 'NOT_TRACKED'),
             ('lions', 'g6', 'seniors', 'HOME', NULL, 'NOT_TRACKED'),
             ('lions', 'g6', 'kara', 'AWAY', NULL, 'NOT_TRACKED'),
             ('eagles', 'g1', 'a', 'HOME', 70, 'DRAFT'),
             ('eagles', 'g1', 'rivals', 'AWAY', 65, 'NOT_TRACKED'))
         AS v(org, game, team, side, score, stats_status)
ON CONFLICT DO NOTHING;

-- -----------------------------------------------------------------------------
-- 8. Feuilles de match (game_participations)
--    Colonnes : match, joueur, statut, titulaire, maillot, secondes, points,
--               reb. off., reb. déf., passes, interceptions, contres, pertes,
--               fautes, +/-   (NULL = non suivi ; DNP = tout à zéro)
--    Invariants respectés : <= 5 titulaires, somme des points PLAYED = score
--    (84, 79, 68 et 70), aucune ligne PENDING sur une feuille validée.
-- -----------------------------------------------------------------------------
INSERT INTO game_participations (id, organization_id, game_id, game_team_id, player_id, status,
                                 is_starter, jersey_number, seconds_played, points,
                                 offensive_rebounds, defensive_rebounds, assists, steals,
                                 blocks, turnovers, personal_fouls, plus_minus, entered_by_user_id)
SELECT pg_temp.sid('gp:lions:' || v.game || ':' || v.player),
       pg_temp.sid('org:lions'),
       pg_temp.sid('game:lions:' || v.game),
       pg_temp.sid('gt:lions:' || v.game || ':seniors'),
       pg_temp.sid('player:lions:' || v.player),
       v.status::participation_status,
       v.starter,
       v.jersey,
       v.sec,
       v.pts,
       v.orb,
       v.drb,
       v.ast,
       v.stl,
       v.blk,
       v.tov,
       v.pf,
       v.pm,
       pg_temp.sid('user:kossi')
FROM (VALUES
          -- g1 : 84-76 (temps et +/- suivis)
          ('g1', 'p1', 'PLAYED', true, 4, 2040, 18, 1, 3, 9, 3, 0, 3, 2, 8),
          ('g1', 'p2', 'PLAYED', true, 7, 1920, 16, 0, 3, 4, 2, 0, 2, 3, 6),
          ('g1', 'p3', 'PLAYED', true, 11, 1860, 14, 1, 5, 3, 1, 1, 1, 2, 9),
          ('g1', 'p4', 'PLAYED', true, 14, 1740, 12, 3, 7, 2, 0, 1, 2, 4, 4),
          ('g1', 'p5', 'PLAYED', true, 23, 1680, 10, 4, 8, 1, 0, 3, 1, 3, 2),
          ('g1', 'p6', 'PLAYED', false, 5, 900, 6, 0, 2, 3, 1, 0, 1, 1, 3),
          ('g1', 'p7', 'PLAYED', false, 9, 720, 5, 0, 1, 1, 1, 0, 0, 2, -2),
          ('g1', 'p8', 'PLAYED', false, 10, 540, 3, 1, 2, 0, 0, 0, 1, 1, 1),
          ('g1', 'p9', 'DNP', false, 15, 0, 0, 0, 0, 0, 0, 0, 0, 0, NULL),
          -- g2 : 71-79, victoire à l'extérieur
          ('g2', 'p1', 'PLAYED', true, 4, 1980, 15, 0, 2, 7, 2, 0, 2, 1, 9),
          ('g2', 'p2', 'PLAYED', true, 7, 2100, 20, 1, 3, 3, 1, 0, 3, 2, 11),
          ('g2', 'p3', 'PLAYED', true, 11, 1800, 12, 2, 4, 2, 2, 1, 1, 3, 7),
          ('g2', 'p4', 'PLAYED', true, 14, 1620, 9, 3, 6, 1, 0, 1, 2, 4, 3),
          ('g2', 'p5', 'PLAYED', true, 23, 1500, 8, 5, 9, 0, 0, 4, 1, 3, 5),
          ('g2', 'p6', 'PLAYED', false, 5, 960, 7, 0, 1, 4, 1, 0, 0, 0, 2),
          ('g2', 'p7', 'PLAYED', false, 9, 600, 4, 0, 2, 1, 0, 0, 1, 1, -1),
          ('g2', 'p8', 'PLAYED', false, 10, 540, 4, 1, 1, 1, 1, 0, 0, 2, 0),
          ('g2', 'p9', 'PLAYED', false, 15, 300, 0, 0, 2, 0, 0, 1, 1, 1, -3),
          -- g3 : 68-72, défaite ; +/- NON SUIVI (NULL) ; p10 (U17) est INVITÉ
          ('g3', 'p1', 'PLAYED', true, 4, 2100, 10, 0, 2, 6, 1, 0, 4, 2, NULL),
          ('g3', 'p2', 'PLAYED', true, 7, 2000, 14, 0, 2, 2, 0, 0, 3, 3, NULL),
          ('g3', 'p3', 'PLAYED', true, 11, 1900, 11, 1, 4, 1, 1, 0, 2, 2, NULL),
          ('g3', 'p4', 'PLAYED', true, 14, 1700, 8, 2, 5, 1, 0, 2, 3, 5, NULL),
          ('g3', 'p5', 'PLAYED', true, 23, 1600, 9, 3, 7, 0, 0, 2, 2, 4, NULL),
          ('g3', 'p6', 'PLAYED', false, 5, 800, 6, 0, 1, 2, 2, 0, 1, 1, NULL),
          ('g3', 'p7', 'PLAYED', false, 9, 500, 5, 1, 0, 0, 0, 0, 0, 1, NULL),
          ('g3', 'p10', 'PLAYED', false, 8, 400, 5, 0, 2, 1, 1, 0, 1, 2, NULL),
          ('g3', 'p8', 'DNP', false, 10, 0, 0, 0, 0, 0, 0, 0, 0, 0, NULL),
          ('g3', 'p9', 'DNP', false, 15, 0, 0, 0, 0, 0, 0, 0, 0, 0, NULL),
          -- g4 : BROUILLON incomplet (lignes PENDING) : jamais dans les statistiques
          ('g4', 'p1', 'PLAYED', true, 4, 2000, 22, 1, 3, 6, 2, 0, 2, 2, NULL),
          ('g4', 'p2', 'PLAYED', true, 7, 1900, 18, 0, 4, 3, 1, 0, 3, 3, NULL),
          ('g4', 'p3', 'PENDING', false, 11, NULL, 0, 0, 0, 0, 0, 0, 0, 0, NULL),
          ('g4', 'p4', 'PENDING', false, 14, NULL, 0, 0, 0, 0, 0, 0, 0, 0, NULL),
          ('g4', 'p5', 'PENDING', false, 23, NULL, 0, 0, 0, 0, 0, 0, 0, 0, NULL),
          ('g4', 'p6', 'PENDING', false, 5, NULL, 0, 0, 0, 0, 0, 0, 0, 0, NULL),
          ('g4', 'p7', 'PENDING', false, 9, NULL, 0, 0, 0, 0, 0, 0, 0, 0, NULL),
          ('g4', 'p8', 'PENDING', false, 10, NULL, 0, 0, 0, 0, 0, 0, 0, 0, NULL),
          ('g4', 'p9', 'PENDING', false, 15, NULL, 0, 0, 0, 0, 0, 0, 0, 0, NULL))
         AS v(game, player, status, starter, jersey, sec, pts, orb, drb, ast, stl, blk, tov, pf, pm)
ON CONFLICT DO NOTHING;

-- Eagles : match 70-65, cinq titulaires (20 + 18 + 14 + 10 + 8 = 70)
INSERT INTO game_participations (id, organization_id, game_id, game_team_id, player_id, status,
                                 is_starter, jersey_number, seconds_played, points,
                                 offensive_rebounds, defensive_rebounds, assists, steals,
                                 blocks, turnovers, personal_fouls, plus_minus, entered_by_user_id)
SELECT pg_temp.sid('gp:eagles:' || v.game || ':' || v.player),
       pg_temp.sid('org:eagles'),
       pg_temp.sid('game:eagles:' || v.game),
       pg_temp.sid('gt:eagles:' || v.game || ':a'),
       pg_temp.sid('player:eagles:' || v.player),
       'PLAYED'::participation_status,
       true,
       v.jersey,
       v.sec,
       v.pts,
       v.orb,
       v.drb,
       v.ast,
       v.stl,
       v.blk,
       v.tov,
       v.pf,
       v.pm,
       pg_temp.sid('user:yao')
FROM (VALUES ('g1', 'e1', 4, 2200, 20, 0, 2, 8, 2, 0, 3, 2, 7),
             ('g1', 'e2', 7, 2100, 18, 1, 3, 3, 1, 0, 2, 3, 5),
             ('g1', 'e3', 11, 2000, 14, 2, 4, 2, 1, 1, 1, 2, 4),
             ('g1', 'e4', 14, 1900, 10, 3, 6, 1, 0, 1, 2, 4, 2),
             ('g1', 'e5', 23, 1800, 8, 4, 7, 0, 0, 3, 1, 3, 1))
         AS v(game, player, jersey, sec, pts, orb, drb, ast, stl, blk, tov, pf, pm)
ON CONFLICT DO NOTHING;

-- -----------------------------------------------------------------------------
-- 9. Validation des feuilles : DRAFT -> VALIDATED, comme dans l'application.
--    Les lignes de feuille ont été écrites tant que la feuille était en brouillon
--    (aucune raison de correction exigée) ; le trigger trace ici la validation.
--    La feuille du match g4 reste volontairement en DRAFT.
--    Le test « stats_status = 'DRAFT' » rend l'opération idempotente.
-- -----------------------------------------------------------------------------
UPDATE game_teams gt
SET stats_status         = 'VALIDATED',
    validated_at         = g.scheduled_at + interval '1 day',
    validated_by_user_id = CASE gt.organization_id
                               WHEN pg_temp.sid('org:lions') THEN pg_temp.sid('user:awa')
                               ELSE pg_temp.sid('user:yao')
        END,
    version              = gt.version + 1,
    updated_at           = now()
FROM games g
WHERE g.id = gt.game_id
  AND g.organization_id = gt.organization_id
  AND gt.stats_status = 'DRAFT'
  AND gt.id IN (pg_temp.sid('gt:lions:g1:seniors'),
                pg_temp.sid('gt:lions:g2:seniors'),
                pg_temp.sid('gt:lions:g3:seniors'),
                pg_temp.sid('gt:eagles:g1:a'));

-- -----------------------------------------------------------------------------
-- 10. Palmarès de la saison 2025-2026 (close). Équipe = instantané à l'attribution.
-- -----------------------------------------------------------------------------
INSERT INTO awards (id, organization_id, season_id, player_id, kind, team_id,
                    awarded_by_user_id, awarded_at, citation)
SELECT pg_temp.sid('award:lions:' || v.kind),
       pg_temp.sid('org:lions'),
       pg_temp.sid('season:lions:2025'),
       pg_temp.sid('player:lions:' || v.player),
       v.kind::award_kind,
       pg_temp.sid('team:lions:seniors'),
       pg_temp.sid('user:awa'),
       '2026-07-01 09:00:00+00'::timestamptz,
       v.citation
FROM (VALUES ('MVP', 'p5', 'Pilier de la raquette sur toute la saison'),
             ('BEST_DEFENDER', 'p4', 'Meilleur contreur et meilleur rebondeur défensif'))
         AS v(kind, player, citation)
ON CONFLICT DO NOTHING;

-- Nettoyage : la fonction temporaire disparaît avec la session, on la retire par hygiène.
DROP FUNCTION IF EXISTS pg_temp.sid(text);
