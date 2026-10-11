# Contribuer à Arcway

Ce document décrit comment on travaille sur le backend. Il est volontairement court : une règle qui n'est pas appliquée
est retirée.

## Prérequis

- Java 17
- Docker et Docker Compose v2
- Sous Windows : Git Bash
- Maven n'est pas à installer : utiliser le wrapper `./mvnw`

## Démarrer

```bash
cp .env.example .env                                      # puis remplacer chaque CHANGE_ME
docker compose up -d --wait                               # PostgreSQL 17 et Mailpit
./mvnw spring-boot:run -Dspring-boot.run.profiles=local   # lit .env, migre la base, charge les données de démo
```

Le profil `local` charge `.env` lui-même : il n'y a rien à exporter. Pour repartir d'une base vide :
`scripts/dev-reset-db.sh`.

## Branches

- `main` est toujours dans un état déployable. On n'y pousse jamais directement.
- Une branche par sujet, courte et nommée selon le type de changement :
  `feat/invitation-acceptance`, `fix/last-admin-race`, `chore/bump-flyway`, `docs/tenancy`.
- Une branche vit quelques jours, pas quelques semaines. Un gros sujet se découpe.

## Commits

Format [Conventional Commits](https://www.conventionalcommits.org/). **Le message est toujours en anglais.**

```
<type>(<scope>): <summary in the imperative, no trailing period>
```

Le scope est un module (`identity`, `organization`, `team`, `player`, `competition`, `game`, `award`, `audit`,
`statistics`, `common`, `platform`) ou `db`, `deps`, `ci`, `docker` pour le reste.

| Type       | Usage                                                   |
|------------|---------------------------------------------------------|
| `feat`     | nouvelle fonctionnalité                                 |
| `fix`      | correction de bug                                       |
| `refactor` | changement de structure sans changement de comportement |
| `test`     | ajout ou modification de tests                          |
| `docs`     | documentation                                           |
| `chore`    | build, dépendances, configuration                       |
| `ci`       | pipeline                                                |

Exemples : `feat(organization): add member role change`, `fix(game): reject sheet validation with pending lines`.

Un commit = un changement cohérent. Le message explique le **pourquoi** quand il n'est pas évident.

## Règles de conception

- **Une règle vit à un seul endroit** : en base (clé étrangère, `CHECK`, unicité, RLS) ou dans le Java (workflows,
  permissions, invariants multi-lignes), jamais dans les deux.
- Java 17 uniquement. La `Clock` est injectée : jamais de `Instant.now()` ni de `LocalDate.now()`.
- Les agrégats se référencent par identifiant (`UUID`), pas par `@ManyToOne`.
- Un module n'utilise d'un autre que son package racine ; `ArchitectureTest` le vérifie.
- Nommage SQL : `pk_`, `fk_`, `uq_`, `ck_`, `ex_`, `ix_`, `trg_`. Renommer après le gel est un changement de contrat
  d'API.

## Pull requests

Même seul, on passe par une PR : c'est elle qui déclenche la CI et laisse une trace des décisions. Le modèle
`.github/pull_request_template.md` se remplit automatiquement. La protection de branche exige le job **CI status**.

Avant de demander une revue, vérifier :

- [ ] `./mvnw verify` passe en local ;
- [ ] le code respecte `.editorconfig` ;
- [ ] aucune donnée sensible dans le diff (mots de passe, tokens, emails réels) ;
- [ ] **impact multi-tenant** : toute nouvelle table tenant a `organization_id`, la RLS et des FK composites ;
- [ ] **permission** : tout nouvel endpoint `/orgs/**` déclare `@RequiresPermission` ou `@OpenToMembers` ;
- [ ] **migration** : voir la section suivante ;
- [ ] la documentation est mise à jour si le comportement change.

Les PR de Dependabot suivent la même règle : CI complète avant fusion, sans exception.

## Revue

Seul : relire son propre diff dans l'interface GitHub avant de fusionner. On y voit ce qu'on ne voit pas dans l'IDE.
À plusieurs : au moins une approbation, et jamais de fusion de sa propre PR sur un sujet de sécurité (authentification,
isolation, permissions).

## Migrations de base de données

- Elles vivent dans `src/main/resources/db/migration`.
- **Versionnées** : `V<numéro à 3 chiffres>__<description_snake_case>.sql` (tables, colonnes, contraintes, index,
  enums).
  Un enum est créé dans la migration de la table qui l'utilise.
- **Répétables** : `R__<nnn>_<description>.sql` (vue, politiques RLS, droits). Elles doivent être idempotentes.
- **Avant la première livraison en production**, la suite peut être modifiée librement, puis la base locale
  recréée (`scripts/dev-reset-db.sh`). **Après**, une migration versionnée fusionnée n'est plus jamais modifiée :
  Flyway en enregistre l'empreinte et la modifier casse tous les environnements déjà migrés. On crée une nouvelle
  migration.
- Toute contrainte et tout index reçoivent un **nom explicite** : l'API s'en sert pour produire ses codes d'erreur.
- Pas de retour arrière SQL : on ajoute d'abord, on bascule, puis on supprime dans une version ultérieure (expand /
  contract).

## Tests

| Niveau                        | Convention | Commande        | Quand                      |
|-------------------------------|------------|-----------------|----------------------------|
| Unitaires (sans Docker)       | `*Test`    | `./mvnw test`   | à chaque modification      |
| Intégration (PostgreSQL réel) | `*IT`      | `./mvnw verify` | avant de pousser, et en CI |

On teste sur PostgreSQL (Testcontainers), jamais sur H2 : RLS, triggers et contraintes d'exclusion n'y existent pas.
Aucun mock de repository.

Un bug corrigé reçoit un test qui échoue sans le correctif.

## Secrets

- Jamais dans Git, jamais dans une image, jamais dans un log.
- `.env` est ignoré. `.env.example` ne contient que des noms et des valeurs factices (`CHANGE_ME`).
- gitleaks tourne en CI sur tout l'historique.
- Un secret poussé par erreur est **compromis** : le révoquer, pas seulement le supprimer du dépôt.

## Sécurité

Pour signaler une vulnérabilité, ne pas ouvrir d'issue : voir [SECURITY.md](SECURITY.md).
