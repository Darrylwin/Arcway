-- Extensions requises par le modèle de données.
--   citext     : colonnes texte insensibles à la casse (email, slug).
--   btree_gist : contraintes d'exclusion mêlant égalité et plages de dates
--   pg_trgm    : recherche floue de noms (détection de doublons de joueurs).
--
-- Ces trois extensions sont « trusted » : le propriétaire de la base peut les
-- installer sans être superuser, ce qui est le cas du rôle migrator.
CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
