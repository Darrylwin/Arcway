# Instructions pour les assistants de code (Arcway)

Arcway est une plateforme multi-tenant de statistiques de basketball : backend
Spring Boot, Java 17, PostgreSQL 17, monolithe modulaire. Ces règles sont
contraignantes : une proposition qui les enfreint est à corriger avant revue.

## Langue

- Code, noms, colonnes, routes, codes d'erreur : **anglais**.
- Documentation et commentaires de conception : **français**.
- Messages de commit et titres de PR : **anglais**, format `type(scope): message`.

## Java 17 uniquement

- Autorisé : `record`, `sealed`, blocs de texte, expressions `switch`, `instanceof`
  avec motif, `Stream.toList()`.
- Interdit : motifs de décomposition de `record`, `switch` à motifs, threads
  virtuels, `SequencedCollection`, `List.getFirst()` / `getLast()`.
- Jamais `Instant.now()` ni `LocalDate.now()` : utiliser la `Clock` injectée.
- Identifiants : `UUID.randomUUID()` du JDK.

## Architecture

- Package racine `com.darcode.arcway`, un package de premier niveau par module.
- Un module n'utilise d'un autre que son **package racine**, jamais `domain/`,
  `repository/`, `service/` ni `web/`. Aucun cycle.
- Organisation d'un module : `domain/` (entités, enums, politiques, sans Spring
  hors `jakarta.persistence`), `repository/`, `service/`, `web/` (contrôleurs,
  `Request` et `Response` en `record`).
- Références entre agrégats **par identifiant** (`UUID`), jamais par `@ManyToOne`.
- Une interface n'existe que s'il y a plusieurs implémentations réelles ou une
  inversion de dépendance nécessaire.
- Contrôleurs : conversion et appel de service uniquement. Aucune règle métier,
  aucun accès au repository.
- Aucune entité JPA dans `web/` ni dans un `record` de la racine d'un module.
- Seul `identity` accède à `users`. Seul `statistics` lit
  `v_official_player_games`, et il ne lit aucune autre table.

## Règle d'or : une règle vit à un seul endroit

PostgreSQL garantit ce qui concerne une ligne, une relation ou une unicité (FK,
`CHECK`, `UNIQUE`, exclusion, RLS). L'application garantit les workflows
(transitions, validation de feuille, permissions, invariants multi-lignes). Ne
jamais dupliquer une règle dans les deux couches.

## Transactions, tenant, concurrence

- Tout `@Service` qui accède à la base est `@Transactional` (ou
  `@Transactional(readOnly = true)`). Hors transaction, la RLS renvoie zéro ligne.
- `organization_id` est rempli depuis `TenantContext`, jamais depuis un corps de
  requête. Aucun `*Request` n'a de champ `organizationId`.
- Pas de `SET` de session : uniquement `set_config(..., true)`.
- Toute FK vers une table tenant est **composite** `(colonne, organization_id)`.
- Verrou optimiste (`version`) sur `games`, `game_teams`, `memberships` ; verrou
  pessimiste sur `organizations` pour le retrait du dernier `ADMIN` ; `UPDATE`
  conditionnel pour l'acceptation d'invitation et la rotation de refresh.

## Autorisation

- Toute méthode de service appelée par un contrôleur `/orgs/**` porte
  `@RequiresPermission` ou `@OpenToMembers`.
- La matrice vit dans `PermissionMatrix` ; toute modification apparaît en revue.

## Erreurs

- `DomainException` est la seule exception métier. Codes stables
  `ARCWAY_<MODULE>_<MOTIF>`, catégorie → statut HTTP.
- Les erreurs de contrainte PostgreSQL sont traduites **par nom de contrainte**
  (`XxxConstraintErrors`). Jamais de message SQL vers le client.

## Base de données

- Nommage : `pk_`, `fk_`, `uq_`, `ck_`, `ex_`, `ix_`, `trg_`. Changer un nom après
  le gel est un changement de contrat d'API.
- Migrations `V###` immuables après la première livraison en production. Objets
  re-créables (vue, politiques, droits) dans les `R__`.
- Aucune suppression physique pour : `users`, `organizations`, `teams`, `players`,
  `seasons`, `competitions`, `games`, `awards`. `ON DELETE RESTRICT` partout.
- Aucun index hors modèle sans plan d'exécution qui le justifie.

## Tests

- `XxxTest` : unitaire (Surefire, sans Docker). `XxxIT` : PostgreSQL réel
  (Failsafe, Testcontainers).
- **Aucun mock de repository ni de base** : une garantie de PostgreSQL ne se simule pas.
- Chaque comportement est testé une fois, au plus bas niveau qui expose son risque.
- Toute opération concurrente : test à deux transactions, échec sans protection,
  succès avec.
- Toute nouvelle route `/orgs/**` : cas dans `AuthorizationApiIT` ; `CrossTenantApiIT`
  la découvre seul.

## Sécurité

- Aucun secret dans le dépôt. Aucun corps de requête, `Authorization`, mot de
  passe, jeton, email ou date de naissance dans les logs.
- Dépendance ajoutée uniquement si Spring Boot ou le JDK ne suffit pas.
