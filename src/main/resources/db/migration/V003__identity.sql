-- =============================================================================
-- V003 : identité
-- -----------------------------------------------------------------------------
-- users, auth_sessions, one_time_tokens
-- Un utilisateur n'est jamais supprimé physiquement : anonymisation.
-- Le token en clair n'est jamais stocké : seul son hash SHA-256 l'est.
-- =============================================================================

CREATE TYPE one_time_token_purpose AS ENUM ('EMAIL_VERIFICATION', 'PASSWORD_RESET');

-- -----------------------------------------------------------------------------
-- users
-- -----------------------------------------------------------------------------
CREATE TABLE users
(
    id                uuid        NOT NULL DEFAULT gen_random_uuid(),
    email             citext      NOT NULL,               -- identifiant de connexion
    password_hash     text,                               -- Argon2id encodé ; NULL après anonymisation
    first_name        text        NOT NULL,
    last_name         text        NOT NULL,
    locale            text        NOT NULL DEFAULT 'fr',
    email_verified_at timestamptz,
    last_login_at     timestamptz,
    deleted_at        timestamptz,                        -- renseigné à l'anonymisation
    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now(), -- renseignée par l'application

    CONSTRAINT pk_users PRIMARY KEY (id),
    CONSTRAINT uq_users_email UNIQUE (email),
    CONSTRAINT ck_users_locale CHECK (locale ~ '^[a-z]{2}(-[A-Z]{2})?$')
);

-- -----------------------------------------------------------------------------
-- auth_sessions : un refresh token = une ligne.
-- Une rotation crée une ligne dans la même famille et marque l'ancienne rotated_at.
-- Réutilisation d'un token déjà tourné : toute la famille est révoquée.
-- -----------------------------------------------------------------------------
CREATE TABLE auth_sessions
(
    id         uuid        NOT NULL DEFAULT gen_random_uuid(),
    user_id    uuid        NOT NULL,
    family_id  uuid        NOT NULL, -- regroupe les rotations d'une même connexion
    token_hash bytea       NOT NULL, -- SHA-256 du token opaque
    expires_at timestamptz NOT NULL,
    rotated_at timestamptz,          -- token échangé contre un nouveau
    revoked_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT pk_auth_sessions PRIMARY KEY (id),
    CONSTRAINT fk_auth_sessions_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CONSTRAINT uq_auth_sessions_token_hash UNIQUE (token_hash),
    CONSTRAINT ck_auth_sessions_expiry CHECK (expires_at > created_at)
);

CREATE INDEX ix_auth_sessions_family ON auth_sessions (family_id);
CREATE INDEX ix_auth_sessions_user_active ON auth_sessions (user_id)
    WHERE revoked_at IS NULL AND rotated_at IS NULL;
CREATE INDEX ix_auth_sessions_expiry ON auth_sessions (expires_at);
-- nettoyage des expirés

-- -----------------------------------------------------------------------------
-- one_time_tokens : vérification d'email (24 h) et réinitialisation (1 h).
-- Usage unique.
-- -----------------------------------------------------------------------------
CREATE TABLE one_time_tokens
(
    id           uuid                   NOT NULL DEFAULT gen_random_uuid(),
    user_id      uuid                   NOT NULL,
    purpose      one_time_token_purpose NOT NULL,
    token_hash   bytea                  NOT NULL,
    target_email citext, -- adresse en cours de vérification
    expires_at   timestamptz            NOT NULL,
    consumed_at  timestamptz,
    created_at   timestamptz            NOT NULL DEFAULT now(),

    CONSTRAINT pk_one_time_tokens PRIMARY KEY (id),
    CONSTRAINT fk_one_time_tokens_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CONSTRAINT uq_one_time_tokens_token_hash UNIQUE (token_hash),
    CONSTRAINT ck_one_time_tokens_target_email
        CHECK (purpose <> 'EMAIL_VERIFICATION' OR target_email IS NOT NULL)
);

CREATE INDEX ix_one_time_tokens_user_pending ON one_time_tokens (user_id, purpose)
    WHERE consumed_at IS NULL;
CREATE INDEX ix_one_time_tokens_expiry ON one_time_tokens (expires_at);
