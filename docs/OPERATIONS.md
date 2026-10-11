# Arcway : guide d'exploitation

Public : exploitants et responsables de déploiement. Ce guide s'appuie sur les
fichiers du dépôt : `deploy/`, `scripts/`, `ops/db/init/01-roles.sql`,
`.github/workflows/release.yml`. En cas d'écart entre ce guide et ces fichiers, **les fichiers font foi** : corriger le
guide dans la même PR.

## 1. Vue d'ensemble

```text
Internet ──► Caddy (80/443, TLS) ──► app (API, port 8080, non publié)
                                       │  └─ Actuator : 127.0.0.1:<ARCWAY_MANAGEMENT_PORT> (hôte)
                                       └──► PostgreSQL 17 (EXTERNE, TLS vérifié)
```

| Élément     | Rôle                                                          |
|-------------|---------------------------------------------------------------|
| `migrate`   | Étape one-shot : Flyway (`arcway_migrator`), puis arrêt       |
| `app`       | API, rôle `arcway_app` (aucun DDL, RLS toujours appliquée)    |
| `caddy`     | Seul service exposé : TLS, en-têtes, limite de corps          |
| Base        | Hors de ce dépôt ; rôles créés par `ops/db/init/01-roles.sql` |
| Sauvegardes | `scripts/backup-db.sh` (chiffrées, hors du serveur de base)   |

Principes : aucun secret dans Git ni dans l'image ; secrets montés comme
fichiers ; une règle vit à un seul endroit ; un redémarrage de quelques secondes
est accepté en V1 (pas de haute disponibilité).

## 2. Prérequis

**Serveur applicatif** : Linux, Docker Engine et Docker Compose v2, `curl`,
pare-feu n'ouvrant que 22 (restreint), 80 et 443. DNS du domaine public pointé
vers le serveur avant le premier démarrage (défi ACME).

**Base PostgreSQL 17** : TLS activé, accès réseau limité à l'IP du serveur
applicatif et à celle de la machine de sauvegarde. Une base `arcway` vide,
créée par un compte d'administration.

**Machine de sauvegarde** : `pg_dump` (version majeure ≥ serveur), `age`,
`sha256sum`, accès réseau à la base.

**GitHub** : environnement `production` avec relecteurs obligatoires ; secrets
`DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_SSH_KEY`, `DEPLOY_KNOWN_HOSTS`.

## 3. Première installation

### 3.1 Utilisateur et arborescence

```bash
sudo adduser --disabled-password --gecos "" deploy
sudo usermod -aG docker deploy          # le groupe docker équivaut à root : clé SSH dédiée, restreinte
sudo install -d -o deploy -g deploy /opt/arcway /opt/arcway/deploy /opt/arcway/scripts
sudo install -d -o deploy -g deploy /opt/arcway/deploy/env /opt/arcway/deploy/certs
sudo install -d -o root -g root -m 0700 /opt/arcway/deploy/secrets
```

### 3.2 Rôles de base de données

Depuis un poste de confiance, avec un compte d'administration :

```bash
export ARCWAY_DB_MIGRATOR_PASSWORD="$(openssl rand -base64 36 | tr -d '\n')"
export ARCWAY_DB_APP_PASSWORD="$(openssl rand -base64 36 | tr -d '\n')"
psql "host=db.example.com dbname=arcway user=<admin> sslmode=verify-full" \
     -v ON_ERROR_STOP=1 -f ops/db/init/01-roles.sql
```

Conserver les deux mots de passe pour l'étape 3.3, puis les effacer de
l'environnement du shell (`unset`).

### 3.3 Secrets

Un fichier par secret, **sans retour à la ligne final**, lisible par l'UID 10001 (utilisateur du conteneur) et par
personne d'autre.

```bash
cd /opt/arcway/deploy/secrets
write_secret() {                       # write_secret <NOM> <valeur>
  ( umask 077; printf '%s' "$2" | sudo tee "$1" >/dev/null )
  sudo chown 10001:10001 "$1"; sudo chmod 0400 "$1"
}
write_secret ARCWAY_DB_APP_PASSWORD      '<mot de passe arcway_app>'
write_secret ARCWAY_DB_MIGRATOR_PASSWORD '<mot de passe arcway_migrator>'
write_secret ARCWAY_JWT_SECRET           "$(openssl rand -base64 48 | tr -d '\n')"   # 32 octets minimum
write_secret ARCWAY_MAIL_USER            '<utilisateur SMTP>'
write_secret ARCWAY_MAIL_PASSWORD        '<mot de passe SMTP>'
```

### 3.4 Configuration et certificat de la base

```bash
cd /opt/arcway/deploy
cp env/prod.env.example env/prod.env && chmod 600 env/prod.env   # puis adapter chaque valeur
# CA du serveur PostgreSQL (fournie par l'hébergeur de la base) :
cp /chemin/vers/ca.pem certs/db-ca.pem && chmod 644 certs/db-ca.pem
```

### 3.5 Premier déploiement

Créer un tag `vX.Y.Z` (voir section 4). Le pipeline envoie `compose.prod.yaml`,
`Caddyfile` et le smoke test, migre la base, démarre l'API et vérifie.

## 4. Déploiement

### 4.1 Par le pipeline (nominal)

1. Mettre à jour la version du `pom.xml`, fusionner dans `main`.
2. `git tag vX.Y.Z && git push origin vX.Y.Z`
3. `release.yml` : tests, image, scan, publication (par condensat).
4. **Approuver** le déploiement dans GitHub (environnement `production`).
5. Migration → démarrage → smoke test. En cas d'échec : retour arrière automatique.

### 4.2 Manuel (secours)

```bash
cd /opt/arcway
export ARCWAY_IMAGE=ghcr.io/<org>/arcway@sha256:<condensat>
compose=(docker compose --env-file deploy/env/prod.env -f deploy/compose.prod.yaml)
"${compose[@]}" pull
timeout 300 "${compose[@]}" run --rm --no-deps migrate
"${compose[@]}" up -d --no-deps --wait --wait-timeout 240 app caddy
printf '%s\n' "$ARCWAY_IMAGE" > .current-image
bash scripts/smoke-test.sh --base-url https://<domaine> --management-url http://127.0.0.1:<port>
```

### 4.3 Règle des migrations : expand / contract

Une migration **ajoute** sans supprimer ; la suppression d'une colonne arrive à
la version suivante. Toute migration doit rester compatible avec la version
précédente de l'application : c'est ce qui rend le retour arrière sans toucher
à la base possible. Les migrations `V###` sont immuables après la première
livraison en production.

## 5. Retour arrière

Automatique en cas d'échec du déploiement ou du smoke test. Manuel :

```bash
cd /opt/arcway
export ARCWAY_IMAGE="$(< .previous-image)"
docker compose --env-file deploy/env/prod.env -f deploy/compose.prod.yaml \
  up -d --no-deps --wait app
printf '%s\n' "$ARCWAY_IMAGE" > .current-image
```

La base n'est **pas** restaurée. Si une migration incompatible a été livrée (violation de la règle 4.3) : arrêter l'API,
restaurer la sauvegarde (section 6)
vers une base neuve, puis rediriger l'application.

## 6. Sauvegarde et restauration

### 6.1 Sauvegarde nocturne

Sur la machine de sauvegarde, variables dans un fichier root-only (`/etc/arcway-backup.env`, mode 0600) :

```bash
PGHOST=db.example.com
PGDATABASE=arcway
PGSSLMODE=verify-full
PGSSLROOTCERT=/etc/arcway/db-ca.pem
ARCWAY_DB_MIGRATOR_PASSWORD_FILE=/etc/arcway/migrator.pw
BACKUP_AGE_RECIPIENT=age1...            # clé PUBLIQUE uniquement
BACKUP_DIR=/var/backups/arcway          # hors du volume de la base
BACKUP_RETENTION_DAYS=30
BACKUP_POST_HOOK=/opt/arcway/scripts/offsite-copy.sh   # copie HORS SITE (à fournir)
```

Cron (02:00 UTC) :

```cron
0 2 * * * set -a; . /etc/arcway-backup.env; set +a; /opt/arcway/scripts/backup-db.sh >> /var/log/arcway-backup.log 2>&1
```

Une sauvegarde qui reste sur la même machine ou le même disque que la base
n'est pas une sauvegarde : le crochet doit pousser le fichier ailleurs.
La **clé privée age** ne doit jamais se trouver sur un serveur de production (coffre hors ligne).

### 6.2 Test de restauration mensuel (obligatoire)

Une sauvegarde jamais restaurée n'est pas prouvée. Chaque mois, depuis un poste
de confiance :

```bash
export PGHOST=<serveur de test> PGUSER=<admin> ARCWAY_DB_ADMIN_PASSWORD_FILE=<fichier>
scripts/restore-db.sh --file <dernier.dump.age> --identity <cle-privee-age> \
                      --target-db arcway_restore_test --replace
```

Contrôler les résultats affichés (tables, tables avec RLS activée, dernière
migration Flyway, nombre d'utilisateurs et d'organisations) face à la
production, noter la date et le résultat dans le registre d'exploitation, puis
supprimer la base d'essai :

```bash
psql -d postgres -c 'DROP DATABASE arcway_restore_test WITH (FORCE)'
```

### 6.3 Reprise après sinistre

1. Provisionner un serveur PostgreSQL neuf ; exécuter `ops/db/init/01-roles.sql`.
2. `restore-db.sh --target-db arcway --allow-production-target` avec la dernière
   sauvegarde valide.
3. Mettre à jour `ARCWAY_DB_URL` (et la CA si besoin), puis redémarrer :
   `up -d --no-deps --force-recreate app`.
4. Smoke test. Les données postérieures à la sauvegarde sont perdues (point de reprise : 24 h au maximum avec la
   sauvegarde nocturne).

## 7. Rotation des secrets

| Secret                | Procédure                                                                                                                                                                       | Effet                                                                                                                                                  |
|-----------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------|
| `ARCWAY_JWT_SECRET`   | Écrire le nouveau fichier (3.3), puis `up -d --no-deps --force-recreate app`                                                                                                    | Les jetons d'accès en cours (10 min) sont invalidés ; les refresh tokens, en base, restent valides : les clients se reconnectent de façon transparente |
| Mots de passe base    | Écrire le nouveau fichier, rejouer `01-roles.sql` avec les nouveaux mots de passe en variables (resynchronise les rôles), puis recréer `app` aussitôt                           | Brève fenêtre où les nouvelles connexions échouent jusqu'au redémarrage                                                                                |
| SMTP                  | Écrire les fichiers, recréer `app`                                                                                                                                              | Aucun effet visible                                                                                                                                    |
| Clé age de sauvegarde | Générer une nouvelle paire hors ligne, changer `BACKUP_AGE_RECIPIENT` ; **conserver l'ancienne clé privée** tant que des sauvegardes chiffrées avec elle sont dans la rétention | Les anciennes sauvegardes restent lisibles                                                                                                             |

Suspicion de compromission d'un secret : le faire tourner immédiatement. Pour le
secret JWT, la rotation déconnecte tout le monde : c'est voulu.

## 8. Incidents : premiers réflexes

```bash
compose=(docker compose --env-file deploy/env/prod.env -f deploy/compose.prod.yaml)
"${compose[@]}" ps
"${compose[@]}" logs --since 15m app
curl -s http://127.0.0.1:<port>/actuator/health/readiness
```

Les journaux de l'API sont du JSON : `... logs app | jq 'select(.["log.level"]=="ERROR")'`.
Le canal de sécurité se filtre par logger : `select(.["log.logger"]=="SECURITY")`.

| Symptôme                                                | Vérifier                                                                                                                                           |
|---------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------|
| Readiness DOWN                                          | Base joignable ? certificat TLS valide ? mot de passe synchronisé avec le secret ?                                                                 |
| L'API ne démarre pas                                    | Message de démarrage : propriété ou secret manquant, secret JWT < 32 octets, `RlsStartupVerifier` (rôle avec BYPASSRLS, RLS absente sur une table) |
| `migrate` échoue                                        | Journal de l'étape ; l'API en service n'est pas touchée. Corriger la migration, nouveau tag                                                        |
| Erreurs 500 avec `SECURITY` / `42501` dans les journaux | **Alerte de sécurité** : une requête a violé la RLS. Isoler la requête (`requestId`), ne pas la traiter comme un simple 403                        |
| Pic de 429                                              | Attaque par force brute probable ; consulter les IP côté Caddy ; ajuster `arcway.ratelimit`                                                        |
| Certificat TLS expiré ou refusé                         | Port 80 ouvert ? DNS correct ? volume `caddy-data` conservé ? `logs caddy`                                                                         |
| Disque plein                                            | `docker system df` ; rotation des journaux déjà en place (10 Mo x 5) ; purger les anciennes images                                                 |
| 401 inattendus après déploiement                        | Secret JWT changé (voir 7)                                                                                                                         |

## 9. Purge d'une organisation

Opération d'exploitation, **jamais applicative** : exécutée par `arcway_migrator`
(propriétaire, contourne la RLS). Irréversible. Demande écrite du client conservée.
Préalable obligatoire : sauvegarde fraîche **et** répétition complète sur une copie
restaurée de la production.

Points de vigilance : toutes les clés étrangères sont `RESTRICT` (l'ordre
compte) ; `games.replaces_game_id` référence la même table ; le trigger d'audit
des feuilles empêcherait de supprimer des lignes d'une feuille validée (raison
exigée) et réécrirait dans `audit_log` : il est désactivé le temps de la
transaction. Les comptes `users` (tables globales) ne sont **pas** supprimés par
cette procédure : leur anonymisation est une opération distincte.

```sql
-- psql -d arcway -v org='<uuid de l''organisation>' -f org-purge.sql
\set ON_ERROR_STOP on
BEGIN;

ALTER TABLE game_participations
    DISABLE TRIGGER trg_game_participations_audit;

UPDATE games
SET replaces_game_id = NULL
WHERE organization_id = :'org';

DELETE
FROM awards
WHERE organization_id = :'org';
DELETE
FROM game_participations
WHERE organization_id = :'org';
DELETE
FROM game_teams
WHERE organization_id = :'org';
DELETE
FROM games
WHERE organization_id = :'org';
DELETE
FROM competition_teams
WHERE organization_id = :'org';
DELETE
FROM competitions
WHERE organization_id = :'org';
DELETE
FROM seasons
WHERE organization_id = :'org';
DELETE
FROM roster_entries
WHERE organization_id = :'org';
DELETE
FROM team_staff
WHERE organization_id = :'org';
DELETE
FROM invitations
WHERE organization_id = :'org';
DELETE
FROM memberships
WHERE organization_id = :'org';
DELETE
FROM players
WHERE organization_id = :'org';
DELETE
FROM teams
WHERE organization_id = :'org';
DELETE
FROM audit_log
WHERE organization_id = :'org';
DELETE
FROM organizations
WHERE id = :'org';

ALTER TABLE game_participations
    ENABLE TRIGGER trg_game_participations_audit;

-- Contrôle avant validation : doit afficher 0 partout.
SELECT 'organizations' AS t, count(*)
FROM organizations
WHERE id = :'org'
UNION ALL
SELECT 'players', count(*)
FROM players
WHERE organization_id = :'org'
UNION ALL
SELECT 'games', count(*)
FROM games
WHERE organization_id = :'org'
UNION ALL
SELECT 'audit_log', count(*)
FROM audit_log
WHERE organization_id = :'org';

COMMIT; -- remplacer par ROLLBACK si un contrôle est non nul
```

Le `DISABLE TRIGGER` prend un verrou exclusif bref sur `game_participations` :
exécuter hors heures de pointe. Une fois la procédure validée sur la copie, la
figer dans un fichier `org-purge.sql` versionné.

## 10. Surveillance et maintenance courante

- **Disponibilité** : une sonde externe sur une route publique (par exemple
  `GET /api/v1/me` doit répondre 401) ; la readiness n'est lisible que depuis le
  serveur (`curl http://127.0.0.1:<port>/actuator/health/readiness`).
- **Hebdomadaire** : relire les PR Dependabot (CI complète obligatoire avant
  fusion) ; vérifier l'espace disque ; vérifier que la sauvegarde de la nuit existe.
- **Mensuel** : test de restauration (6.2) ; revue des accès GitHub et SSH.
- **Sécurité** : mises à jour du système hôte, de Docker et de l'image `caddy:2`
  (`pull` puis `up -d caddy`) ; expiration du certificat de la base.
- **PostgreSQL** : montée de version majeure = projet à part (restauration vers
  une base neuve et validation par la suite de tests d'intégration).

## 11. Checklist de release

- [ ] `./mvnw verify` vert en local ; CI verte sur `main`
- [ ] Migrations compatibles avec la version précédente (règle 4.3)
- [ ] Version du `pom.xml` = tag
- [ ] Changement de contrat d'API signalé (nom de contrainte, code d'erreur, formule de la vue)
- [ ] Sauvegarde de la veille présente ; test de restauration du mois fait
- [ ] Tag poussé, déploiement approuvé, smoke test vert
- [ ] Notes de version GitHub générées
