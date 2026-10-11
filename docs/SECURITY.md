# Politique de sécurité

## Signaler une vulnérabilité

**Ne publiez pas de vulnérabilité dans une issue, une discussion ou une pull request publique.**

Utilisez l'un de ces deux canaux privés :

1. **Recommandé** : l'onglet *Security* du dépôt, puis *Report a vulnerability*
   (signalement privé GitHub).
2. **Email** : `logossoudarryl20@gmail.com`

Merci d'inclure, si possible :

- la description de la faille et son impact ;
- les étapes pour la reproduire (requêtes, payloads, version ou commit) ;
- toute piste de correction.

## Ce que vous pouvez attendre

Arcway est maintenu par une seule personne. Les délais ci-dessous sont des objectifs, pas des garanties contractuelles :

| Étape                                    | Objectif         |
|------------------------------------------|------------------|
| Accusé de réception                      | 5 jours ouvrés   |
| Première évaluation (recevable, gravité) | 10 jours ouvrés  |
| Correctif ou plan de correction          | selon la gravité |

Nous vous tiendrons informé de l'avancement et vous créditerons dans l'avis de sécurité si vous le souhaitez.

## Périmètre

Sont particulièrement importantes pour ce projet :

- toute fuite de données **entre organisations** (isolation multi-tenant, contournement de la RLS) ;
- le contournement de l'authentification (jetons d'accès, refresh tokens, invitations) ou des permissions ;
- l'élévation de privilèges (par exemple devenir `ADMIN` d'une organisation, ou agir sur une équipe hors de son
  périmètre) ;
- l'injection (SQL, en-têtes) ;
- l'exposition de secrets ou de données personnelles, en particulier celles des joueurs mineurs (date de naissance).

Hors périmètre : les attaques par déni de service volumétrique, l'ingénierie sociale, et les rapports issus d'un scanner
automatique sans impact démontré.

## Mécanismes de défense prévus par la conception

Pour orienter vos recherches, voici ce sur quoi la sécurité du projet repose :

- **Isolation entre organisations** : sécurité au niveau ligne PostgreSQL (RLS), clés étrangères composites
  `(colonne, organization_id)`, et accès HTTP par l'organisation de l'URL, relue à chaque requête. Un non-membre reçoit
  404.
- **Rôle de base applicatif** sans droit de propriété, sans `BYPASSRLS`, sans DDL ; démarrage refusé si ces conditions
  ne sont pas réunies.
- **Authentification** : mots de passe hachés en Argon2id ; jetons d'accès JWT de 10 minutes ; refresh tokens à
  rotation,
  stockés sous forme de hash, avec révocation de toute la famille en cas de réutilisation.
- **Secrets** : jamais dans Git ni dans l'image ; montés comme fichiers en production ; détection par gitleaks en CI.
- **Chaîne de livraison** : analyse de l'image (Trivy), revue des dépendances, mises à jour automatiques (Dependabot),
  déploiement par condensat d'image après approbation manuelle.

Cette liste décrit l'architecture visée ; l'avancement de chaque mécanisme suit le développement du projet.

## Versions supportées

Le projet n'a pas encore de version stable. Seule la branche `main` reçoit des correctifs de sécurité.

## Divulgation

Nous demandons une divulgation coordonnée : merci de ne rien rendre public avant qu'un correctif soit disponible ou que
nous en ayons convenu ensemble.
