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
