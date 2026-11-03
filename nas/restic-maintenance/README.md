# Maintenance des dépôts restic sur le NAS

Les VM écrivent dans rest-server en `--append-only` : elles ne peuvent ni supprimer ni nettoyer leurs sauvegardes. La rétention et le contrôle tournent donc **sur le NAS**, directement sur les fichiers des dépôts, sans passer par le réseau.

## Fonctionnement

`restic-maintenance.sh`, chaque dimanche à 5 h (deux heures après les sauvegardes de 3 h), pour chaque fichier `<vm>.password` :

1. `restic forget --group-by host --keep-weekly 4 --prune` : garde la dernière sauvegarde de chacune des 4 dernières semaines.
2. `restic check` : vérifie la structure du dépôt.

| Choix | Pourquoi |
|---|---|
| Conteneur `restic/restic:0.18.0` (`--rm`, `--network none`) | Rien à installer sur UGOS, même version que sur les VM, aucun accès réseau |
| `--user 1000:10` | Les fichiers du dépôt appartiennent à l'utilisateur de rest-server (`0600`) : lancé en root, le nettoyage créerait des fichiers illisibles par rest-server |
| `--group-by host` | Une VM = un seul groupe de rétention, même si la liste des dossiers sauvegardés change |
| Script et secrets sur `/volume1` | Le volume de données survit aux mises à jour d'UGOS, contrairement au système |

Le NAS détient le mot de passe de chaque dépôt (nécessaire pour nettoyer) : un accès root au NAS donne accès aux sauvegardes.

## Installation (sur le NAS, root)

```sh
install -d -m 700 /volume1/backups/restic-maintenance/secrets
install -m 700 restic-maintenance.sh /volume1/backups/restic-maintenance/
# Un fichier par dépôt, copié depuis la VM sans être affiché, puis :
chown 1000:10 /volume1/backups/restic-maintenance/secrets/<vm>.password
chmod 400 /volume1/backups/restic-maintenance/secrets/<vm>.password
# Crontab root
0 5 * * 0 /volume1/backups/restic-maintenance/restic-maintenance.sh >> /volume1/backups/restic-maintenance/maintenance.log 2>&1
```

## Résultat obtenu

Le 2026-11-03, NAS UGREEN DXP4800 (UGOS, Debian 12, Docker 29.6.2), dépôt `gitlab` :

- Mot de passe du dépôt copié de la VM vers `secrets/gitlab.password` par un tube `tsh ssh … | tsh ssh …`, jamais affiché ; `400`, propriété `1000:10`.
- Crontab root : `0 5 * * 0 …/restic-maintenance.sh >> …/maintenance.log 2>&1`.
- Premier passage manuel : `exit=0`, `check` : `no errors were found`. Fichiers du dépôt toujours en `1000:10` ; la VM relit le dépôt ensuite (`restic-nas snapshots`).
- `forget` a gardé 2 snapshots : la sauvegarde GitLab et le snapshot de test, marqué `oldest weekly snapshot`. Restic 0.18 conserve le plus ancien tant que les 4 semaines ne sont pas remplies ; il disparaîtra ensuite.

## Pièges rencontrés

- Volume du NAS rempli à 96 % (345 Go libres sur 7,3 To) au moment de l'installation : à surveiller.

## Limites

- Persistance de la crontab root après une mise à jour d'UGOS : **à vérifier**.
- Pas d'alerte en cas d'échec : lire `maintenance.log`.
- `check` ne relit pas toutes les données (pas de `--read-data`).
