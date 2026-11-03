# rest-server : cible des sauvegardes restic sur le NAS

Les VM sont reconstruites par Terraform et Ansible ; seules leurs **données utiles** sont sauvegardées, avec restic, vers un [rest-server](https://github.com/restic/rest-server) en Docker sur le NAS (UGREEN DXP4800, Docker uniquement, pas de VM).

## Choix

| Choix | Pourquoi |
|---|---|
| rest-server plutôt que MinIO | Seul usage : restic. Plus simple, et mode `--append-only` impossible à obtenir aussi simplement en S3 |
| `--append-only` | Une VM compromise peut écrire de nouvelles sauvegardes mais ni supprimer ni réécrire les anciennes (rançongiciel) |
| `--private-repos` | Un compte par VM, chacun limité à son dépôt (`gitlab` → `/gitlab/`) |
| Image épinglée `0.14.0` | Montée de version volontaire |
| Non root, système de fichiers en lecture seule, `cap_drop: ALL` | Configuration documentée par le projet (« Run without root or a writable root filesystem ») |
| Port publié sur l'IP LAN du NAS uniquement | Aucune redirection depuis Internet |

Le nettoyage (`restic forget --prune`) ne passe **pas** par le serveur : il est interdit en `--append-only`. Il sera lancé sur le NAS, directement sur le dossier des dépôts (étape suivante).

## Déploiement (sur le NAS)

```sh
# Copier compose.yaml et .env.example dans un dossier du NAS, puis :
cp .env.example .env        # adapter les valeurs
mkdir -p "<REST_SERVER_DATA>" && chown <PUID>:<PGID> "<REST_SERVER_DATA>"
docker compose config       # vérifier la configuration résolue
docker compose up -d
docker compose logs         # attendu : avertissement « No user exists » au premier démarrage

# Un compte par VM, mot de passe saisi à l'invite masquée (htpasswd -B)
docker exec -it rest-server create_user gitlab
```

Si le compte n'est pas reconnu juste après sa création : `docker compose restart`.

## Vérification (depuis la VM gitlab)

Les secrets se saisissent à l'invite masquée, jamais en argument (restic ≥ 0.17 pour `RESTIC_REST_USERNAME` / `RESTIC_REST_PASSWORD`) :

```sh
export RESTIC_REPOSITORY=rest:http://<ip-nas>:8000/gitlab/
export RESTIC_REST_USERNAME=gitlab
read -rs RESTIC_REST_PASSWORD && export RESTIC_REST_PASSWORD
restic init                 # demande le mot de passe du dépôt (à conserver hors infra)
restic snapshots            # attendu : dépôt vide, pas d'erreur
```

Contrôles de sécurité attendus :
- un autre compte sur `/gitlab/` → refus (`--private-repos`) ;
- `restic forget <id>` depuis la VM → refus (`--append-only`).

## Résultat obtenu

Le 2026-11-03, NAS UGREEN DXP4800 (projet Docker UGOS), VM `gitlab` (Debian 13, restic 0.18.0) :

- Démarrage : `Authentication enabled`, `Append only mode enabled`, `Private repositories enabled`, `start server on [::]:8000`.
- `restic init` : dépôt créé (version 2).
- `restic backup /tmp/t` : snapshot enregistré.
- `restic forget <id>` depuis la VM : refusé, `unexpected HTTP response (403): 403 Forbidden`. Le mode `--append-only` fonctionne.
- Non testé : l'accès d'un autre compte au dépôt `/gitlab/` (un seul compte existe pour l'instant).

## Pièges rencontrés

- **Éditeur de projets Docker UGOS** : il a refusé ce `compose.yaml` (« fichier de configuration invalide ») et a accepté la même configuration avec les valeurs écrites en dur à la place des variables `${…}`. La cause exacte n'a pas été isolée.
- **`touch: /data/.htpasswd: Permission denied`** : le dossier de données n'appartenait pas à l'utilisateur du conteneur (`user:`). Correction : `chown <PUID>:<PGID>` puis `chmod 750` sur le dossier. Ne pas utiliser `chmod 777`.

## Limites

- **HTTP en clair sur le LAN** : les données sont chiffrées par restic côté client, mais le mot de passe HTTP du compte circule en clair. Passage en TLS (`--tls`, certificat interne) à prévoir.
- Le **mot de passe de chaque dépôt restic** doit être conservé hors de l'infrastructure (gestionnaire de mots de passe) : sans lui, la sauvegarde est illisible.
- Une seule copie, sur le NAS : pas encore de copie hors site (règle 3-2-1 incomplète).
