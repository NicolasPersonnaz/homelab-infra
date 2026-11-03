# Rôle restic : sauvegarde des données utiles vers le NAS

Les VM sont reconstruites par Terraform et Ansible : seules leurs **données** sont sauvegardées, chaque semaine, avec restic, vers le rest-server du NAS ([nas/rest-server](../../../nas/rest-server/README.md)). Avant une mise à jour risquée, un snapshot Proxmox de la VM sert au retour arrière rapide.

## Ce que fait le rôle

| Élément | Détail |
|---|---|
| `restic` | Paquet Debian (0.18.0 sur Debian 13) |
| `/etc/restic/password`, `/etc/restic/rest-password` | Mot de passe du dépôt et du compte rest-server, root `0600`, contenu brut (aucun échappement à gérer). Saisis au prompt (`no_log`), un vide garde le fichier existant |
| `/usr/local/sbin/restic-nas` | `restic` déjà configuré pour le dépôt de la VM : `restic-nas snapshots`, `restic-nas restore …` |
| `/usr/local/sbin/restic-backup` | Commandes préalables (`restic_pre_commands`), `restic backup` des `restic_paths`, puis commandes de fin (`restic_post_commands`) seulement si tout a réussi (`set -euo pipefail`) |
| `restic-backup.timer` | Dimanche 3 h (`restic_on_calendar`), `Persistent=true` : rattrape une sauvegarde manquée. Journaux dans journald |

La VM ne peut ni supprimer ni nettoyer ses sauvegardes (rest-server en `--append-only`) : la rétention (4 dernières sauvegardes hebdomadaires) est appliquée par le NAS.

## GitLab (`host_vars/gitlab.yml`)

Le code est aussi poussé sur GitHub ; la sauvegarde vise surtout ce que GitHub n'a pas.

| Sauvegardé | Pourquoi |
|---|---|
| `gitlab-backup create SKIP=artifacts,registry` | Base (issues, utilisateurs, variables CI, runners), dépôts, état Terraform (`terraform_state`, backend HTTP de la CI). Artefacts CI et images du registre sont régénérables |
| `/etc/gitlab/gitlab-secrets.json` | **Indispensable** : non inclus dans `gitlab-backup`, sans lui les variables CI et les secrets chiffrés de la base sont perdus |
| `/etc/gitlab/gitlab.rb` | Non inclus dans `gitlab-backup` (aussi régénéré par le rôle `gitlab`) |

L'archive locale est supprimée avant chaque export et après une sauvegarde réussie : elle ne s'accumule pas sur la VM.

## Commandes

```sh
cd ansible
ansible-lint --profile production
ansible-playbook gitlab.yml --tags restic --check --diff
ansible-playbook gitlab.yml --tags restic   # mots de passe à l'invite masquée (vides ensuite)

# Sur la VM
systemctl list-timers restic-backup.timer
systemctl start restic-backup.service && journalctl -u restic-backup.service -e
restic-nas snapshots
```

## Restauration

```sh
restic-nas restore latest --target /tmp/restauration
```

Puis, sur une VM `gitlab` reconstruite **avec la même version** de GitLab : remettre `gitlab-secrets.json` et `gitlab.rb` dans `/etc/gitlab`, copier l'archive dans `/var/opt/gitlab/backups`, puis suivre la procédure officielle `gitlab-backup restore`.

## Résultat obtenu

Le 2026-11-03, VM `gitlab` (GitLab 19.5.1, restic 0.18.0) :

- `ansible-lint --profile production` : 0 échec, 0 avertissement. `--check --diff` : `failed=0`.
- 1er passage `--tags restic` : `changed=5` ; 2e passage : `changed=0`.
- Secrets : `/etc/restic/password` et `rest-password` en `600 root`.
- Timer : prochaine exécution `Sun 2026-11-08 03:00:00 CET`.
- Première sauvegarde (`systemctl start restic-backup.service`) : 37 s, snapshot `7a6461f9`, 1,55 Mio ajoutés, archive locale supprimée ensuite.
- Contenu du snapshot : `gitlab-secrets.json`, `gitlab.rb`, archive `…_19.5.1_gitlab_backup.tar` contenant `db/database.sql.gz`, `repositories/` (bundles), `uploads.tar.gz`, `terraform_state.tar.gz`.
- Test de restauration (fichiers) : `restic-nas restore latest --target /tmp/restauration-test --verify` (9 fichiers et dossiers, vérification OK) ; `gitlab-secrets.json` et `gitlab.rb` identiques à ceux de la VM (`cmp`) ; archive extraite, `database.sql.gz` intègre (`gzip -t`, 1739 `CREATE TABLE`), `uploads` et `terraform_state` lisibles, 2 bundles git lisibles (`git bundle list-heads`), `gitlab_version: 19.5.1`.
- Non fait : restauration complète de GitLab sur une VM jetable (`gitlab-backup restore`).

## Pièges rencontrés

- `401 Unauthorized` au premier `restic-nas snapshots` : mauvais mot de passe du compte rest-server déposé. Corrigé en redéposant le fichier ; le rôle n'a pas eu à être rejoué.
- En `--check`, l'activation du timer échoue (unité pas encore écrite) : `ignore_errors: "{{ ansible_check_mode }}"` sur cette seule tâche.

## Limites

- Pas d'alerte en cas d'échec : il faut lire `journalctl -u restic-backup.service` (alerte à prévoir dans la supervision).
- L'archive `gitlab-backup` est un tar de fichiers compressés : restic la déduplique mal d'une semaine à l'autre.
- Le dépôt est inutilisable sans son mot de passe : il doit être conservé hors de l'infrastructure.
