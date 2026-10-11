-- =============================================================================
-- V004 : tenant et appartenances
-- -----------------------------------------------------------------------------
-- Pas de colonne « propriétaire » : les droits d'administration viennent des
-- appartenances ADMIN. Une organisation n'est jamais supprimée.
-- La RLS de ces deux tables est spécifique.
-- =============================================================================

CREATE TYPE org_role AS ENUM ('ADMIN', 'ANALYST', 'VIEWER');

-- -----------------------------------------------------------------------------
-- organizations
-- -----------------------------------------------------------------------------
CREATE TABLE organizations
(
    id                 uuid        NOT NULL DEFAULT gen_random_uuid(), -- fournie par l'application
    name               text        NOT NULL,
    slug               text        NOT NULL,                           -- immuable
    timezone           text        NOT NULL DEFAULT 'UTC',             -- IANA, validé par l'application
    archived_at        timestamptz,
    created_by_user_id uuid        NOT NULL,
    created_at         timestamptz NOT NULL DEFAULT now(),
    updated_at         timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT pk_organizations PRIMARY KEY (id),
    CONSTRAINT uq_organizations_slug UNIQUE (slug),
    CONSTRAINT ck_organizations_slug CHECK (slug ~ '^[a-z0-9-]{3,63}$'),
    CONSTRAINT fk_organizations_created_by FOREIGN KEY (created_by_user_id)
        REFERENCES users (id) ON DELETE RESTRICT
);

-- -----------------------------------------------------------------------------
-- memberships
-- Un utilisateur retiré puis réinvité réactive la MÊME ligne.
-- scope_all_teams n'a de sens que pour ANALYST.
-- version : verrou optimiste, valeur 0 à la création.
-- -----------------------------------------------------------------------------
CREATE TABLE memberships
(
    id               uuid        NOT NULL DEFAULT gen_random_uuid(),
    organization_id  uuid        NOT NULL,
    user_id          uuid        NOT NULL,
    role             org_role    NOT NULL,
    scope_all_teams  boolean     NOT NULL DEFAULT false,
    joined_at        timestamptz NOT NULL DEFAULT now(),
    ended_at         timestamptz,                                  -- NULL = appartenance active
    ended_by_user_id uuid,
    version          bigint      NOT NULL DEFAULT 0,
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT pk_memberships PRIMARY KEY (id),
    CONSTRAINT uq_memberships_org_user UNIQUE (organization_id, user_id),
    CONSTRAINT uq_memberships_id_org UNIQUE (id, organization_id), -- cible des FK composites
    CONSTRAINT fk_memberships_organization FOREIGN KEY (organization_id)
        REFERENCES organizations (id) ON DELETE RESTRICT,
    CONSTRAINT fk_memberships_user FOREIGN KEY (user_id)
        REFERENCES users (id) ON DELETE RESTRICT,
    CONSTRAINT fk_memberships_ended_by FOREIGN KEY (ended_by_user_id)
        REFERENCES users (id) ON DELETE RESTRICT,
    CONSTRAINT ck_memberships_scope_analyst_only CHECK (role = 'ANALYST' OR scope_all_teams = false),
    CONSTRAINT ck_memberships_ended_by CHECK (ended_by_user_id IS NULL OR ended_at IS NOT NULL)
);

CREATE INDEX ix_memberships_user_active ON memberships (user_id) WHERE ended_at IS NULL;
CREATE INDEX ix_memberships_org_role_active ON memberships (organization_id, role) WHERE ended_at IS NULL;
