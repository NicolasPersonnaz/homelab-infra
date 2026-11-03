# Rôle proxmox_snapshot : point de retour avant une mise à jour

Snapshot Proxmox de la VM, pris **à la demande** juste avant une mise à jour risquée, pour revenir en arrière en quelques secondes. Ce n'est pas une sauvegarde : le snapshot vit sur le même stockage que la VM (les données sont sauvegardées par le rôle `restic`).

## Utilisation

```sh
cd ansible
ansible-playbook snapshot.yml -l gitlab                 # snapshot seul, n'importe quelle VM
ansible-playbook gitlab.yml --tags all,snapshot         # snapshot, puis tout le playbook
ansible-playbook gitlab.yml                             # sans snapshot (tags [never, snapshot])
```

Retour arrière : interface Proxmox, **VM > Snapshots > Rollback**, sur le snapshot `avant_maj_<date>`.

## Choix

| Choix | Pourquoi |
|---|---|
| Tags `[never, snapshot]` dans `gitlab.yml` | Jamais pris par défaut : seulement quand on le demande avant une mise à jour |
| API Proxmox depuis le contrôleur (`community.proxmox`) | Rien à exécuter sur la VM ni sur l'hôte, pas d'accès SSH à l'hyperviseur |
| Jeton de Terraform (`/root/.config/homelab/proxmox-token`, lu comme `tf.sh`) | Pas de nouveau secret ; tâches en `no_log` |
| VM retrouvée par son nom | Le nom Ansible = le nom Terraform/Proxmox ; refus si 0 ou plusieurs VM portent ce nom |
| Rétention : 3 snapshots `avant_maj_*` | Un snapshot qui s'accumule ralentit les écritures et occupe le stockage. Les snapshots manuels (autre nom) ne sont jamais supprimés : l'option `retention` du module, elle, compte **tous** les snapshots |
| Sans la RAM (`vmstate: false`) | Plus rapide et plus léger ; au retour arrière, la VM redémarre comme après une coupure |

## Résultat obtenu

Le 2026-11-03, VM `gitlab`, `community.proxmox` 1.3.0 :

- `ansible-lint --profile production` : 0 échec, 0 avertissement.
- `snapshot.yml` sans `-l` : refusé (`Préciser la ou les VM`).
- `snapshot.yml -l gitlab` : `avant_maj_20261103_173348` créé (`python3-proxmoxer` installé sur `gestion` au premier passage). Le jeton de Terraform a les droits nécessaires.
- Rétention : au 4ᵉ passage, le plus ancien a été supprimé et 3 snapshots `avant_maj_*` restaient.
- `gitlab.yml --list-tasks` : 0 tâche `proxmox_snapshot` sans tag, 10 avec `--tags all,snapshot`.
- Les snapshots de test ont ensuite été supprimés.
- Non fait : retour arrière (rollback) testé.

## Limites

- Snapshot cohérent « comme après une coupure de courant » : GitLab (PostgreSQL) le supporte, mais des écritures en cours peuvent être perdues.
- Le stockage des disques doit accepter les snapshots (LVM-thin, ZFS, qcow2 ; pas le LVM classique).
