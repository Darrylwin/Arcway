-- Types énumérés du modèle et fonctions d'aide communes.
-- Règle d'évolution : ajouter une valeur (ALTER TYPE ... ADD VALUE) est sûr ;
-- retirer ou renommer une valeur exige une migration en plusieurs temps.
-- Les listes qui évoluent souvent (postes, types de récompenses) sont des tables.

-- ---------------------------------------------------------------------------
-- Identité et organisation
-- ---------------------------------------------------------------------------
CREATE TYPE user_status AS ENUM ('ACTIVE', 'SUSPENDED', 'DELETED');
CREATE TYPE client_type AS ENUM ('WEB', 'MOBILE');
CREATE TYPE one_time_token_purpose AS ENUM ('EMAIL_VERIFICATION', 'PASSWORD_RESET');

CREATE TYPE org_type AS ENUM ('CLUB', 'ACADEMY', 'UNIVERSITY', 'LEAGUE', 'OTHER');
CREATE TYPE org_status AS ENUM ('ACTIVE', 'SUSPENDED', 'ARCHIVED', 'PENDING_DELETION');
CREATE TYPE org_visibility AS ENUM ('PRIVATE', 'PUBLIC_READ');
CREATE TYPE org_role AS ENUM ('OWNER', 'ADMIN', 'ANALYST', 'VIEWER');
CREATE TYPE membership_status AS ENUM ('ACTIVE', 'SUSPENDED', 'REMOVED');
CREATE TYPE invitation_status AS ENUM ('PENDING', 'ACCEPTED', 'REVOKED');

-- ---------------------------------------------------------------------------
-- Équipes et calendrier
-- ---------------------------------------------------------------------------
CREATE TYPE staff_role AS ENUM ('HEAD_COACH', 'ASSISTANT_COACH', 'STATS_KEEPER', 'MANAGER');
CREATE TYPE team_gender AS ENUM ('MEN', 'WOMEN', 'MIXED');
CREATE TYPE season_status AS ENUM ('PLANNED', 'ACTIVE', 'CLOSED');
CREATE TYPE competition_type AS ENUM ('LEAGUE', 'CUP', 'TOURNAMENT', 'FRIENDLY');
CREATE TYPE competition_status AS ENUM ('DRAFT', 'ACTIVE', 'COMPLETED', 'CANCELLED');
CREATE TYPE game_status AS ENUM ('SCHEDULED', 'IN_PROGRESS', 'FINISHED', 'POSTPONED', 'CANCELLED');
CREATE TYPE game_side AS ENUM ('HOME', 'AWAY');

-- ---------------------------------------------------------------------------
-- Statistiques, palmarès, traçabilité
-- ---------------------------------------------------------------------------
CREATE TYPE stats_status AS ENUM ('NOT_TRACKED', 'DRAFT', 'SUBMITTED', 'VALIDATED');
CREATE TYPE participation_status AS ENUM (
    'PENDING', 'PLAYED', 'DNP_COACH', 'DNP_INJURED', 'DNP_ABSENT', 'DNP_SUSPENDED'
    );
CREATE TYPE award_scope AS ENUM ('SEASON', 'COMPETITION');
CREATE TYPE actor_kind AS ENUM ('USER', 'SYSTEM', 'PLATFORM_SUPPORT');

-- ---------------------------------------------------------------------------
-- Contexte de session
-- ---------------------------------------------------------------------------
CREATE FUNCTION app_org_id() RETURNS uuid
    LANGUAGE sql
    STABLE PARALLEL SAFE
AS
$$
SELECT NULLIF(current_setting('app.org_id', true), '')::uuid
$$;

CREATE FUNCTION app_user_id() RETURNS uuid
    LANGUAGE sql
    STABLE PARALLEL SAFE
AS
$$
SELECT NULLIF(current_setting('app.user_id', true), '')::uuid
$$;

CREATE FUNCTION app_is_platform_admin() RETURNS boolean
    LANGUAGE sql
    STABLE PARALLEL SAFE
AS
$$
SELECT COALESCE(NULLIF(current_setting('app.platform_admin', true), ''), 'false') = 'true'
$$;

-- ---------------------------------------------------------------------------
-- Horodatage de mise à jour, attaché table par table (trg_<table>_set_updated_at)
-- ---------------------------------------------------------------------------
CREATE FUNCTION set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
AS
$$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;
