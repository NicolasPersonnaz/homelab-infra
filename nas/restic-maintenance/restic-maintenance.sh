#!/bin/bash
# Rétention et contrôle des dépôts restic, lancés sur le NAS directement sur les fichiers :
# rest-server est en --append-only, les VM ne peuvent pas supprimer leurs sauvegardes.
# Un dépôt par fichier <vm>.password dans SECRETS_DIR (root 0400, propriété de RUN_AS).
set -uo pipefail

REPOS_DIR="${REPOS_DIR:-/volume1/backups/restic}"
SECRETS_DIR="${SECRETS_DIR:-/volume1/backups/restic-maintenance/secrets}"
RUN_AS="${RUN_AS:-1000:10}"                 # propriétaire des dépôts, comme le user: de rest-server
IMAGE="${IMAGE:-restic/restic:0.18.0}"      # même version que sur les VM
KEEP_WEEKLY="${KEEP_WEEKLY:-4}"

restic_on() {
  docker run --rm --network none --user "$RUN_AS" \
    -v "$REPOS_DIR/$1:/repo" -v "$SECRETS_DIR/$1.password:/password:ro" \
    -e RESTIC_REPOSITORY=/repo -e RESTIC_PASSWORD_FILE=/password -e RESTIC_CACHE_DIR=/tmp/cache \
    "$IMAGE" "${@:2}"
}

status=0
for password_file in "$SECRETS_DIR"/*.password; do
  [ -e "$password_file" ] || { echo "Aucun fichier .password dans $SECRETS_DIR"; exit 1; }
  repo=$(basename "$password_file" .password)
  echo "=== $(date -Is) $repo"
  # --group-by host : un seul groupe par VM, même si la liste des dossiers change
  if restic_on "$repo" forget --group-by host --keep-weekly "$KEEP_WEEKLY" --prune \
     && restic_on "$repo" check; then
    echo "=== $repo : OK"
  else
    echo "=== $repo : ÉCHEC"
    status=1
  fi
done
exit "$status"
