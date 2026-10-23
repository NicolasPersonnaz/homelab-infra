# Ansible : premier playbook

Objectif : valider la chaîne Ansible sur une VM Debian (cible1).

Prérequis : compte `ansible` avec clé SSH sur la cible, Ansible installé sur la machine de gestion.

Commandes :
    ansible all -m ping
    ansible-playbook playbooks/first.yml --check --diff
    ansible-playbook playbooks/first.yml

Résultat vérifié :
- 1er passage : changed=3
- 2e passage : changed=0 (idempotence)
- après suppression manuelle de `tree` : changed=1, l'état est rétabli

Pièges : un clone duplique les identités (machine-id, clés SSH de l'hôte) ; le mot de passe du compte `ansible` n'a servi qu'à copier la clé.

## Rôles

| Rôle | Rôle dans la baseline |
|---|---|
| common | Paquets de base, fuseau horaire, bannière de connexion (template) |
| users | Comptes et clés SSH publiques, pilotés par la variable `users_list` |
| ssh | Configuration sshd durcie (fichier complémentaire), validée par `sshd -t`, rechargement par handler |
| gitlab | GitLab CE épinglé, HTTPS par CA interne, réglages mémoire, swap. Voir [roles/gitlab/README.md](roles/gitlab/README.md) |
| gitlab_runner | Docker Engine et GitLab Runner (systemd, exécuteur Docker), enregistrement par jeton saisi au prompt |
| ci_image | Image Docker `homelab-ci` des jobs CI, construite localement sur la VM gitlab |
| gitlab_client | Sur la VM de gestion : nom de GitLab et CA interne, pour `git push` et HTTPS (playbook `gestion.yml`) |

## Utilisation

    cd ansible
    ansible-playbook site.yml --check --diff
    ansible-playbook site.yml

## Résultat vérifié

- 1er passage : changed=3 (clé SSH, configuration sshd, handler)
- 2e passage : changed=0 (idempotence)
- Handler : modifier `ssh_max_auth_tries` recharge sshd, et uniquement dans ce cas
- Vérifié sur la cible : `sshd -T` affiche permitrootlogin no et maxauthtries 4

## Pièges rencontrés

- Une erreur dans une clé SSH publique (faute de frappe) fait échouer la tâche : `--syntax-check` ne vérifie pas le contenu des données.
- Une tâche en échec arrête le playbook sur la machine, donc les rôles suivants ne s'exécutent pas.
- `validate: sshd -t -f %s` évite d'écraser un fichier de configuration invalide.
