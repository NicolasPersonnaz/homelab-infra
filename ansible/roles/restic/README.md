# Rôle restic : sauvegarde des données utiles vers le NAS

Les VM sont reconstruites par Terraform et Ansible : seules leurs **données** sont sauvegardées, chaque semaine, avec restic, vers le rest-server du NAS ([nas/rest-server](../../../nas/rest-server/README.md)). Avant une mise à jour risquée, un snapshot Proxmox de la VM sert au retour arrière rapide.

## Ce que fait le rôle

| Élément | Détail |
|---|---|
| `restic` + `restic_extra_packages` | Paquet Debian (0.18.0 sur Debian 13) et outils des commandes préalables (ex. `sqlite3`) |
| `/etc/restic/password`, `/etc/restic/rest-password` | Mot de passe du dépôt et du compte rest-server, root `0600`, contenu brut (aucun échappement à gérer). Déposés hors du rôle (voir « Ajouter une VM ») ; un vide au prompt garde le fichier existant |
| `/usr/local/sbin/restic-nas` | `restic` déjà configuré pour le dépôt de la VM : `restic-nas snapshots`, `restic-nas restore …` |
| `/usr/local/sbin/restic-backup` | Commandes préalables (`restic_pre_commands`), `restic backup` des `restic_paths`, puis commandes de fin (`restic_post_commands`) seulement si tout a réussi (`set -euo pipefail`) |
| `restic-backup.timer` | Dimanche 3 h (`restic_on_calendar`), `Persistent=true` : rattrape une sauvegarde manquée. Journaux dans journald |

La VM ne peut ni supprimer ni nettoyer ses sauvegardes (rest-server en `--append-only`) : la rétention (4 dernières sauvegardes hebdomadaires) est appliquée par le NAS.

## VM sauvegardées

| VM | Playbook | Sauvegardé | Non sauvegardé (recréé) |
|---|---|---|---|
| `gitlab` | `gitlab.yml` | voir ci-dessous | artefacts CI, images du registre |
| `defectdojo` | `defectdojo.yml` | `pg_dump` SQL non compressé (déduplication), `secrets.env` (clés de chiffrement), `config.env`, volume des pièces jointes | images Docker, compose (rôle `defectdojo`) |
| `grafana` | `grafana.yml` | copie cohérente de `grafana.db` (`sqlite3 .backup`, Grafana en marche), `/etc/grafana` | plugins, tableaux de bord provisionnés, historique Prometheus (30 j) |
| `gestion` | `gestion.yml` (`restic_name: gestion`, l'hôte s'appelle `localhost` dans l'inventaire) | CA interne, `~/homelab-teleport`, jeton Proxmox, `terraform.tfvars`, vrais `group_vars` | copie de travail (Git), identité `tbot` (renouvelée) |

`lynis-test` et `hardening-test` n'ont aucune donnée : elles ne sont pas sauvegardées. L'adresse du NAS (`restic_server_url`) est dans `inventories/homelab/group_vars/all.yml` (non versionné).

## Ajouter une VM

Aucun mot de passe n'est saisi ni affiché : ils sont générés aléatoirement et passent d'une machine à l'autre par des tubes `tsh ssh … | tsh ssh …`.

```sh
N=<vm>; NAS=root@<nas>; D=/volume1/backups/restic-maintenance
tsh ssh root@$N "install -d -m 700 /etc/restic"
# Compte rest-server : généré sur le NAS (htpasswd -i lit l'entrée standard), envoyé à la VM
tsh ssh $NAS "pw=\$(head -c 32 /dev/urandom | base64 | tr -d '/+=\n'); printf %s \"\$pw\" | docker exec -i rest-server htpasswd -B -i /data/.htpasswd $N >/dev/null && printf %s \"\$pw\"" \
  | tsh ssh root@$N "umask 077; cat > /etc/restic/rest-password"
# Mot de passe du dépôt : généré sur la VM, copié sur le NAS pour la maintenance
tsh ssh root@$N "umask 077; head -c 32 /dev/urandom | base64 | tr -d '/+=\n' > /etc/restic/password; cat /etc/restic/password" \
  | tsh ssh $NAS "umask 077; cat > $D/secrets/$N.password; chown 1000:10 $D/secrets/$N.password; chmod 400 $D/secrets/$N.password"
# host_vars/<vm>.yml (restic_paths…), rôle restic dans le playbook, puis :
ansible-playbook <playbook>.yml --tags restic
tsh ssh root@$N "restic-nas init && systemctl start restic-backup.service && restic-nas snapshots"
```

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

Le 2026-11-03, `defectdojo`, `grafana`, `gestion` (secrets générés et échangés par tubes, jamais affichés) :

- Déploiement `--tags restic` : `changed=6` puis `changed=0` sur chacune.
- Première sauvegarde : `defectdojo` 1,87 Mio (snapshot `898dea5a`), `grafana` 1,58 Mio (`47dc71ce`), `gestion` 14 Kio (`86628e75`), en 1 s environ chacune ; fichiers temporaires supprimés ensuite.
- Restauration `--verify` : `defectdojo.sql` complet (`PostgreSQL database dump complete`, 208 `CREATE TABLE`), `secrets.env` identique ; `grafana.db` `PRAGMA integrity_check` = `ok`, `grafana.ini` identique ; `gestion` : CA, jeton et `terraform.tfvars` identiques (`diff -r`, `cmp`).
- Isolation : le compte `defectdojo` sur le dépôt `/gitlab/` reçoit `401 Unauthorized` (`--private-repos`).
- Maintenance du NAS sur les 4 dépôts : `exit=0`, `no errors were found` pour chacun.

## Pièges rencontrés

- `401 Unauthorized` au premier `restic-nas snapshots` : mauvais mot de passe du compte rest-server déposé. Corrigé en redéposant le fichier ; le rôle n'a pas eu à être rejoué.
- En `--check`, l'activation du timer échoue (unité pas encore écrite) : `ignore_errors: "{{ ansible_check_mode }}"` sur cette seule tâche.

## Limites

- Pas d'alerte en cas d'échec : il faut lire `journalctl -u restic-backup.service` (alerte à prévoir dans la supervision).
- L'archive `gitlab-backup` est un tar de fichiers compressés : restic la déduplique mal d'une semaine à l'autre.
- Le mot de passe de chaque dépôt n'existe que sur la VM et sur le NAS : si le NAS est perdu, les sauvegardes le sont aussi ; si la VM est perdue, il est relu sur le NAS (`secrets/<vm>.password`).
- AIDE (rôle `hardening`) voit changer `/var/cache/restic` et les dossiers d'export : exclusions à ajouter.
