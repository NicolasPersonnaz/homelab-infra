# Rôle hardening : durcissement Debian 13 mesuré avec Lynis

Rôle construit à partir de l'audit de référence ([docs/lynis-baseline.md](../../../docs/lynis-baseline.md)), développé sur la VM `hardening-test` (même baseline que `lynis-test`) et mesuré avec Lynis dans les mêmes conditions. Les deux rapports sont importés dans DefectDojo.

## Résultat avant / après

| Indicateur | `lynis-test` (référence) | `hardening-test` (rôle appliqué) |
|---|---|---|
| **Indice de durcissement Lynis** | **67** | **85** |
| Tests réalisés | 248 | 264 |
| Avertissements | 2 | 2, tous deux faux positifs vérifiés |
| Suggestions | 44 | 18 |
| DefectDojo (actives) | 2 Medium, 44 Low | 0 Medium, 18 Low |

Même image, même baseline, même version de Lynis (3.1.4, `lynis audit system --quick`), le 2026-10-23.

## Ce que fait le rôle

| Thème | Mesures | Tests Lynis |
|---|---|---|
| SSH | `05-durcissement.conf` : `AllowTcpForwarding no`, `AllowAgentForwarding no`, `LogLevel VERBOSE`, `MaxAuthTries 3`, `MaxSessions 2`, `TCPKeepAlive no`. Nommé `05-` car sshd garde la **première** valeur lue (il passe avant `10-hardening.conf`) | SSH-7408 |
| Pare-feu | nftables, entrée refusée par défaut ; acceptés : boucle locale, connexions établies, ICMP, SSH depuis `gestion`. Aucune ouverture pour Teleport : l'agent est sortant (tunnel inverse) | FIRE-4512 |
| Noyau | 23 paramètres `sysctl` (redirections, routage source, `rp_filter`, `kptr_restrict`, `dmesg_restrict`, BPF, `ptrace_scope`, `protected_*`…) ; modules `dccp`, `sctp`, `rds`, `tipc`, `usb-storage`, `firewire-core` bloqués | KRNL-6000, NETW-3200, USB-1000, STRG-1846 |
| Comptes | `login.defs` (âge des mots de passe, `UMASK 027`, tours de hachage), `libpam-passwdqc`, `libpam-tmpdir` | AUTH-9230, 9262, 9286, 9328, DEB-0280 |
| Audit | `auditd` + 11 règles (identités, sudo, sshd, Teleport, pare-feu), `acct`, `sysstat` | ACCT-9622, 9626, 9628 |
| Intégrité | AIDE (base de référence initialisée une seule fois), `rkhunter`, `debsums` (vérification hebdomadaire) | FINT-4350, HRDN-7230, PKGS-7370 |
| Mises à jour | `needrestart` en mode liste (aucun redémarrage de service imprévu), `apt-show-versions` | DEB-0831, PKGS-7394 |
| Bannières | `/etc/issue` et `/etc/issue.net` bilingues | BANN-7126, 7130 |

## Commandes

```bash
# Sur la VM de gestion
cd ansible
ansible-playbook hardening.yml

# Mesure
tsh ssh root@hardening-test "lynis audit system --quick --no-colors"
```

Import dans DefectDojo : même méthode que pour la référence (voir [docs/lynis-baseline.md](../../../docs/lynis-baseline.md)), produit `hardening-test`, engagement « Audit Lynis après durcissement (rôle hardening) ».

## Résultat vérifié

- Premier passage : `ok=19 changed=16 failed=0`. Passage suivant : `changed=0`.
- Accès conservés : SSH depuis `gestion`, Teleport (`tsh ssh root@hardening-test`).
- SSH direct depuis un autre poste du LAN : port 22 **injoignable** (bloqué par le pare-feu, et plus seulement refusé par sshd).
- `sshd -T` : les 6 valeurs appliquées ; `nft` : `policy drop` et `ip saddr <ip-gestion> tcp dport 22 accept` ; `nftables`, `auditd`, `acct`, `sysstat` actifs ; 11 règles d'audit chargées ; `modprobe -n -v sctp` → `install /bin/false`.
- Lynis : 67 → 83 au premier essai, puis 85 après deux corrections (bannière bilingue, `debsums` hebdomadaire).
- DefectDojo : import `201`, 20 failles, PKGS-7388 et FIRE-4512 marquées faux positifs avec une note de preuve.

## Suggestions Lynis volontairement non suivies

| Test | Pourquoi |
|---|---|
| KRNL-6000 (`kernel.modules_disabled=1`) | Interdirait tout chargement de module jusqu'au redémarrage, y compris ceux que nftables charge à la demande |
| FIRE-4512 | Faux positif : Lynis contrôle les règles iptables legacy, le pare-feu est nftables |
| PKGS-7388 | Faux positif : `trixie-security` est configuré en deb822 avec une URI `mirror+file:` |
| SSH-7408 (port) | Changer le port n'apporte pas de sécurité réelle ; SSH n'est joignable que depuis `gestion` |
| DEB-0880 (`fail2ban`) | Peu utile : le pare-feu n'accepte SSH que depuis `gestion` |
| DEB-0810 (`apt-listbugs`) | Pose des questions à chaque installation : bloquerait Ansible |
| BOOT-5122 (mot de passe GRUB) | La console Proxmox est déjà un accès physique |
| FILE-6310 (`/home`, `/var` séparés) | Relève du template de VM, pas d'Ansible |
| LOGG-2154 (journaux distants) | Pas encore de serveur de journaux dans le homelab |
| FINT-4402 (AIDE en SHA-256/512) | La configuration Debian d'AIDE utilise déjà des empreintes fortes ; Lynis ne la lit pas |
| HRDN-7222 (compilateurs) | `as` (binutils) arrive par dépendance ; une restriction de droits serait annulée à chaque mise à jour sans `dpkg-statoverride` |
| BOOT-5264 (services systemd) | Demande une analyse service par service (`systemd-analyze security`) : étape suivante |
| LYNIS (version) | Version du paquet Debian ; le dépôt CISOfy donnerait la dernière |

## Pièges rencontrés

| Symptôme | Cause | Solution |
|---|---|---|
| `--check` : `Could not find the requested service nftables` | En simulation, le paquet n'est pas réellement installé | Limite du mode `--check` sur une VM neuve |
| Bannières toujours signalées (BANN-7126/7130) | Lynis compte des mots-clés **anglais** (5 au moins) ; le texte français n'en contenait qu'un | Bannière bilingue |
| Réglages SSH sans effet si placés dans un fichier `20-…` | sshd garde la première valeur lue dans `sshd_config.d` | Fichier `05-durcissement.conf` |

## Limites

| Limite | Piste |
|---|---|
| `flush ruleset` dans `/etc/nftables.conf` efface les règles des autres outils | Ne pas appliquer tel quel sur une VM avec Docker (gitlab, defectdojo) : tables dédiées ou intégration des règles Docker |
| Rôle lancé depuis `gestion`, pas encore par la CI | L'ajouter à `homelab.yml` pour les VM sans Docker une fois validé |
| Bases AIDE et rkhunter initialisées une seule fois | Mise à jour volontaire après une modification légitime (`aideinit`, `rkhunter --propupd`) et contrôle planifié |
