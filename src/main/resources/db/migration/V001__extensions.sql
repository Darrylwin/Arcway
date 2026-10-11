-- =============================================================================
-- V001 : extensions PostgreSQL
-- -----------------------------------------------------------------------------
-- citext     : texte insensible à la casse
-- btree_gist : opérateur d'égalité dans un index GiST
--
-- Les deux extensions sont « trusted » : le propriétaire de la base peut les
-- créer sans être superuser.
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA public;
