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

- toute fuite de données **entre organisations** (isolation multi-tenant) ;
- le contournement de l'authentification ou des permissions ;
- l'élévation de privilèges (par exemple devenir OWNER) ;
- l'injection (SQL, en-têtes, fichiers) et l'upload de fichiers malveillants ;
- l'exposition de secrets ou de données personnelles.

Hors périmètre : les attaques par déni de service volumétrique, l'ingénierie sociale, et les rapports issus d'un scanner
automatique sans impact démontré.

## Versions supportées

Le projet n'a pas encore de version stable. Seule la branche `main` reçoit des correctifs de sécurité.

## Divulgation

Nous demandons une divulgation coordonnée : merci de ne rien rendre public avant qu'un correctif soit disponible ou que
nous en ayons convenu ensemble.
