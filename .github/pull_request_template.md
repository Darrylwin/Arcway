<!--
  Titre de la PR : même convention que les commits (en ANGLAIS).
  Exemple : feat(game): add stat sheet validation
  Une PR = un sujet. Supprimer les sections sans objet.
-->

## Objet

<!-- Que change cette PR, et pourquoi ? Lien vers l'issue : Closes #… -->

## Type de changement

- [ ] Fonctionnalité
- [ ] Correction de bug
- [ ] Migration de base de données
- [ ] Sécurité
- [ ] Refactoring sans changement de comportement
- [ ] Infrastructure, build ou CI
- [ ] Documentation

## Checklist obligatoire

### Base de données
- [ ] Aucune migration `V###` déjà livrée en production n'a été modifiée
- [ ] Toute nouvelle table avec `organization_id` : RLS, politique, FK composites, `R__030_grants.sql` à jour
- [ ] Toute nouvelle contrainte (`uq_`, `ck_`, `ex_`) : nom conforme à la convention, ajoutée à `IntegrityConstraintsIT` et à `XxxConstraintErrors`
- [ ] Une règle vit à **un seul endroit** (base ou application, jamais les deux)

### Autorisation et isolation entre organisations
- [ ] Toute méthode de service appelée par un contrôleur `/orgs/**` porte `@RequiresPermission` ou `@OpenToMembers`
- [ ] `PermissionMatrix` modifiée ? Le tableau de référence et `PermissionMatrixTest` sont mis à jour
- [ ] Aucun `*Request` n'expose `organizationId` ; `organization_id` vient de `TenantContext`
- [ ] Impact multi-tenant analysé (nouvelle route couverte par `CrossTenantApiIT`)

### Sécurité et données
- [ ] Aucun secret, jeton, mot de passe, email ou date de naissance dans le code, les logs ou les tests
- [ ] Aucune information technique ne fuit dans les réponses d'erreur

### Contrat d'API
- [ ] Changement de contrat (route, champ, code d'erreur, nom de contrainte, formule de la vue) : signalé ci-dessous

### Qualité
- [ ] Tests ajoutés au plus bas niveau utile (unitaire, `*ServiceIT`, `*ApiIT`), sans mock de repository
- [ ] Test de concurrence si l'opération est concurrente
- [ ] Java 17 uniquement ; `Clock` injectée (pas de `Instant.now()`)
- [ ] `./mvnw verify` passe en local

## Changement de contrat d'API

<!-- « Aucun » ou description et plan de compatibilité. -->

## Plan de retour arrière

<!-- Redéployer l'image précédente suffit-il ? Si non, expliquer. -->

## Captures, extraits de requêtes ou notes de revue

<!-- Optionnel. -->
