<div align="center">
  <h1>Arcway Backend API</h1>

  <img src="assets/arcway.png" alt="Logo Arcway" height="160"/>

  <p>
    <strong>Plateforme multi-tenancy de gestion et d'analyse de performances de basket-ball.</strong>
  </p>

  <!-- Badges d'état du projet -->
  <p>
    <img src="https://img.shields.io/badge/Java-17-orange?style=flat-square&logo=openjdk" alt="Java 17" />
    <img src="https://img.shields.io/badge/Spring%20Boot-4.1.1-brightgreen?style=flat-square&logo=springboot" alt="Spring Boot 4.1.1" />
    <img src="https://img.shields.io/badge/PostgreSQL-17-blue?style=flat-square&logo=postgresql" alt="PostgreSQL 17" />
    <img src="https://img.shields.io/badge/License-AGPL--3.0-blue.svg?style=flat-square" alt="License AGPL-3.0" />
  </p>
</div>

> **Statut : en développement.** Il n'y a pas encore de version stable ; l'API peut changer.

## Présentation

Arcway permet à des organisations (clubs, académies, ligues) de gérer leurs équipes et leurs joueurs, de planifier des
compétitions et des matchs, de saisir et valider les feuilles de match, puis d'analyser les performances à partir de
statistiques officielles.

**Ce que couvre la V1**

- Organisations, membres et rôles (`ADMIN`, `ANALYST`, `VIEWER`), invitations par email
- Équipes, staff, joueurs, effectifs
- Saisons, compétitions, matchs
- Feuilles de match : saisie, soumission, validation, correction tracée
- Statistiques officielles : totaux, moyennes, classements, comparaisons, progression
- Récompenses (MVP, meilleur défenseur, meilleur espoir)

**Ce qui est garanti par conception**

- **Isolation entre organisations** : sécurité au niveau ligne PostgreSQL (RLS), clés étrangères composites, accès HTTP
  par l'organisation de l'URL.
- **Statistiques officielles à définition unique** : une feuille non validée ou un match annulé n'y apparaît jamais.
- **Traçabilité** : toute correction d'une feuille validée exige une raison et conserve l'état avant et après.

## Pile technique

| Sujet           | Choix                                             |
|-----------------|---------------------------------------------------|
| Langage         | Java 17                                           |
| Framework       | Spring Boot 4.1.1 (monolithe modulaire)           |
| Base de données | PostgreSQL 17, migrations Flyway                  |
| Sécurité        | Spring Security, JWT (HS256), Argon2id            |
| Tests           | JUnit, Testcontainers (PostgreSQL réel), ArchUnit |
| Exploitation    | Docker, Caddy (TLS), GitHub Actions               |

## Démarrage rapide (poste de développement)

**Prérequis** : Java 17 (voir `.sdkmanrc`), Docker avec Compose v2, et Git Bash sous Windows. Maven n'est pas à
installer : utiliser `./mvnw`.

```bash
# 1. Cloner
git clone https://github.com/Darrylwin/Arcway.git
cd Arcway

# 2. Configurer : copier le modèle puis remplacer chaque CHANGE_ME
cp .env.example .env
#    ARCWAY_JWT_SECRET             -> openssl rand -base64 48
#    POSTGRES_PASSWORD,
#    ARCWAY_DB_APP_PASSWORD,
#    ARCWAY_DB_MIGRATOR_PASSWORD   -> openssl rand -base64 24   (trois valeurs différentes)

# 3. Démarrer PostgreSQL et Mailpit (crée aussi les rôles de base)
docker compose up -d --wait

# 4. Lancer l'application (migre la base et charge les données de démonstration)
./mvnw spring-boot:run -Dspring-boot.run.profiles=local

# 5. Vérifier
curl http://localhost:8080/actuator/health
```

Emails de développement (invitations, vérification) : <http://localhost:8025> (Mailpit).

**Comptes de démonstration** (profil `local` uniquement), mot de passe commun `Arcway-Demo-2026!` :

| Compte                     | Organisation   | Rôle                                |
|----------------------------|----------------|-------------------------------------|
| `awa.koffi@arcway.test`    | Lions de Lomé  | `ADMIN` (et `VIEWER` aux Eagles)    |
| `kossi.mensah@arcway.test` | Lions de Lomé  | `ANALYST`, équipe « Lions Seniors » |
| `esso.kpetsu@arcway.test`  | Lions de Lomé  | `ANALYST`, toutes les équipes       |
| `ama.dossou@arcway.test`   | Lions de Lomé  | `VIEWER`                            |
| `yao.agbeko@arcway.test`   | Eagles Academy | `ADMIN`                             |

Repartir d'une base vide : `scripts/dev-reset-db.sh`.

## Commandes utiles

```bash
./mvnw test      # tests unitaires (sans Docker)
./mvnw verify    # tests unitaires + tests d'intégration (PostgreSQL via Testcontainers : Docker requis)
./mvnw package -DskipTests   # jar exécutable dans target/
docker build -t arcway:local .   # image de production
```

## Profils et configuration

| Profil    | Usage                                                                     |
|-----------|---------------------------------------------------------------------------|
| `local`   | Développement : lit `.env`, Flyway au démarrage, données de démo, Mailpit |
| `prod`    | Production : journaux JSON, secrets lus depuis des fichiers montés        |
| `migrate` | Étape de migration seule (avec `prod`), exécutée avant chaque déploiement |

Toute la configuration passe par des variables d'environnement documentées dans `.env.example`. Aucun secret n'est
versionné.

## Structure du dépôt

```text
.
├── src/main/java/com/darcode/arcway/   code, un package par module
├── src/main/resources/                 configuration et migrations Flyway (db/migration)
├── src/test/                           tests (*Test unitaires, *IT PostgreSQL réel)
├── ops/db/init/01-roles.sql            création des rôles PostgreSQL
├── scripts/                            réinitialisation locale, sauvegarde, restauration, smoke test
├── deploy/                             déploiement de production (Compose, Caddy)
├── docs/                               documentation
├── compose.yml                         PostgreSQL et Mailpit (développement)
└── Dockerfile                          image de production
```

Modules : `common`, `platform`, `identity`, `organization`, `team`, `player`, `competition`, `game`, `award`, `audit`,
`statistics`. Un module n'utilise d'un autre que son package racine (vérifié par `ArchitectureTest`).

## Documentation

- [Modèle de données](docs/data/arcway-modele-de-donnees.md) : schéma de référence
- [Exploitation](docs/OPERATIONS.md) : déploiement, retour arrière, sauvegarde et restauration, incidents
- [Contribuer](docs/CONTRIBUTING.md) : branches, commits, pull requests, migrations, tests
- [Sécurité](docs/SECURITY.md) : signaler une vulnérabilité
- [Code de conduite](docs/CODE_OF_CONDUCT.md)

## Contribuer

Les règles de travail sont dans [CONTRIBUTING.md](docs/CONTRIBUTING.md). Pour signaler une vulnérabilité, ne pas ouvrir
d'issue : voir [SECURITY.md](docs/SECURITY.md).

## Licence

Arcway est distribué sous licence AGPL-3.0. Voir [LICENSE](LICENSE).
