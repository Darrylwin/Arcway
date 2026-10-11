# Contribuer à Arcway

Ce document décrit comment on travaille sur le backend. Il est volontairement court : une règle qui n'est pas appliquée
est retirée.

## Prérequis

- Java 17 (voir `.sdkmanrc`)
- Docker et Docker Compose
- Maven n'est pas à installer : utiliser le wrapper `./mvnw`

## Démarrer

```bash
cp .env.example .env        # puis remplacer les valeurs "change-me"
docker compose up -d --wait # PostgreSQL et Mailpit
```

Spring Boot ne lit pas `.env` : exporter les variables avant de lancer l'application.

```bash
set -a; source .env; set +a
./mvnw spring-boot:run
```

## Branches

- `main` est toujours dans un état déployable. On n'y pousse jamais directement.
- Une branche par sujet, courte et nommée selon le type de changement :
  `feat/invitation-acceptance`, `fix/last-owner-race`, `chore/bump-flyway`, `docs/tenancy`.
- Une branche vit quelques jours, pas quelques semaines. Un gros sujet se découpe.

## Commits

Format [Conventional Commits](https://www.conventionalcommits.org/) :

```
<type>(<module>): <résumé à l'impératif, sans point final>
```

| Type       | Usage                                                   |
|------------|---------------------------------------------------------|
| `feat`     | nouvelle fonctionnalité                                 |
| `fix`      | correction de bug                                       |
| `refactor` | changement de structure sans changement de comportement |
| `test`     | ajout ou modification de tests                          |
| `docs`     | documentation                                           |
| `chore`    | build, dépendances, configuration                       |
| `ci`       | pipeline                                                |

Exemples : `feat(organization): add ownership transfer`, `fix(game): reject sheet validation with pending lines`.

Un commit = un changement cohérent. Le message explique le **pourquoi** quand il n'est pas évident.

## Pull requests

Même seul, on passe par une PR : c'est elle qui déclenche la CI et laisse une trace des décisions.

Avant de demander une revue, vérifier :

- [ ] les tests passent en local ;
- [ ] le code est formaté ;
- [ ] aucune donnée sensible dans le diff (mots de passe, tokens, emails réels) ;
- [ ] **impact multi-tenant** : toute nouvelle table tenant a `organization_id`, la RLS et des FK composites ;
- [ ] **permission** : tout nouvel endpoint déclare la permission requise ;
- [ ] **migration** : voir la section suivante ;
- [ ] la documentation est mise à jour si le comportement change.

## Revue

Seul : relire son propre diff dans l'interface GitHub avant de fusionner. On y voit ce qu'on ne voit pas dans l'IDE.
À plusieurs : au moins une approbation, et jamais de fusion de sa propre PR sur un sujet de sécurité (authentification,
isolation, permissions).

## Migrations de base de données

- Les migrations vivent dans `src/main/resources/db/migration`.
- Nommage : `V<numéro à 3 chiffres>__<description_snake_case>.sql`.
- **Une migration déjà fusionnée n'est jamais modifiée.** Flyway en enregistre l'empreinte : la modifier casse tous les
  environnements déjà migrés. On crée une nouvelle migration.
- Toute contrainte et tout index reçoivent un **nom explicite** : l'API s'en sert pour produire ses codes d'erreur.
- Pas de retour arrière SQL. On ajoute d'abord, on bascule, puis on supprime dans une version ultérieure.

## Tests

| Niveau                        | Convention | Quand                      |
|-------------------------------|------------|----------------------------|
| Unitaires                     | `*Test`    | à chaque modification      |
| Intégration (PostgreSQL réel) | `*IT`      | avant de pousser, et en CI |

On teste sur PostgreSQL, jamais sur H2 : RLS, triggers et contraintes d'exclusion n'y existent pas.

Un bug corrigé reçoit un test qui échoue sans le correctif.

## Secrets

- Jamais dans Git, jamais dans une image, jamais dans un log.
- `.env` est ignoré. `.env.example` ne contient que des noms et des valeurs factices.
- Un secret poussé par erreur est **compromis** : le révoquer, pas seulement le supprimer du dépôt.

## Sécurité

Pour signaler une vulnérabilité, ne pas ouvrir d'issue : voir `SECURITY.md`.
