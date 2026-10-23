# Audit Lynis de référence (avant durcissement)

Mesure « avant » sur la VM `lynis-test`, créée par le pipeline avec la **baseline actuelle** du homelab (rôles `common`, `users`, `ssh` avec SSH direct limité à `gestion`, agent Teleport). Le futur rôle de durcissement sera développé et mesuré sur une autre VM, puis comparé à cette référence.

## Conditions

| Élément | Valeur |
|---|---|
| Date | 2026-10-23 14:13 |
| Système | Debian GNU/Linux 13 (trixie), noyau 6.12.113-1 |
| Lynis | 3.1.4 (paquet Debian) |
| Commande | `lynis audit system --quick --no-colors` (en root, par Teleport) |
| Rapport brut | `/root/lynis-baseline-report.dat` sur la VM |

## Résultat

| Indicateur | Valeur |
|---|---|
| **Indice de durcissement** | **67 / 100** |
| Tests réalisés | 248 |
| Avertissements | 2 |
| Suggestions | 44 |

### Avertissements

| Test | Constat |
|---|---|
| PKGS-7388 | Aucun dépôt de sécurité trouvé. **Faux positif vérifié** : `debian.sources` (format deb822) contient `trixie-security`, actif selon `apt-cache policy` (`a=stable-security`) ; Lynis ne reconnaît pas l'URI `mirror+file:` de l'image cloud |
| FIRE-4512 | Modules iptables chargés mais aucune règle active (pas de pare-feu local) |

### Suggestions, regroupées par thème

| Thème | Tests | Pistes pour le rôle de durcissement |
|---|---|---|
| SSH | SSH-7408 ×7 | `AllowTcpForwarding no`, `AllowAgentForwarding no`, `LogLevel VERBOSE`, `MaxAuthTries 3`, `MaxSessions 2`, `TCPKeepAlive no` (le changement de port est un faux gain) |
| Authentification | AUTH-9230, 9262, 9284, 9286 ×2, 9328 | Tours de hachage et âge des mots de passe dans `login.defs`, `libpam-passwdqc`, `UMASK 027` |
| Noyau et réseau | KRNL-6000, NETW-3200 ×4, USB-1000, STRG-1846 | Paramètres `sysctl` (profil Lynis), désactiver `dccp`, `sctp`, `rds`, `tipc`, stockage USB et firewire |
| Journalisation et audit | ACCT-9622, 9626, 9628, LOGG-2154 | `auditd`, comptabilité des processus, `sysstat`, envoi des journaux vers un hôte distant |
| Paquets | DEB-0280, 0810, 0831, 0880, PKGS-7370, 7394 | `libpam-tmpdir`, `needrestart`, `debsums`, `apt-show-versions`, `fail2ban` (peu utile avec SSH limité à `gestion`) |
| Intégrité et malware | FINT-4350, HRDN-7230 | AIDE (intégrité des fichiers), analyseur de malware |
| Démarrage | BOOT-5122, 5180, 5264 | Mot de passe GRUB (la console Proxmox reste un accès physique), durcissement des services systemd (`systemd-analyze security`) |
| Bannières | BANN-7126, 7130 | Bannière légale dans `/etc/issue` et `/etc/issue.net` |
| Partitions | FILE-6310 ×2 | `/home` et `/var` séparés : décision au niveau du template, pas d'Ansible |
| Divers | FILE-7524, NAME-4028, KRNL-5788, TOOL-5002, LYNIS | Permissions de fichiers, domaine DNS, lien `/vmlinuz` absent (image cloud), version de Lynis du paquet Debian |

Certaines suggestions sont des faux positifs ou des compromis à documenter plutôt qu'à suivre, par exemple le changement de port SSH ou `fail2ban` alors que SSH n'est ouvert qu'à `gestion`.
