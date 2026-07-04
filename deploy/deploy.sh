#!/bin/bash
# storage-lucien/deploy/deploy.sh <SITE>-<ID> — lance ce nœud storage sur ce
# serveur. Suppose generate-config.sh déjà exécuté pour ce site/nœud.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

KEY="${1:?usage: ./deploy.sh <site>-<node-id>  (ex: grenoble-1)}"
[ -f "sites/${KEY}/.env" ] || { echo "sites/${KEY}/.env introuvable — lancez d'abord generate-config.sh ..." >&2; exit 1; }

# shellcheck disable=SC1090
SITE=$(grep '^SITE=' "sites/${KEY}/.env" | cut -d= -f2)
docker network create "dc-${SITE}-lan" > /dev/null 2>&1 || true

docker compose -f docker-compose.prod.yml --env-file "sites/${KEY}/.env" up -d --build
echo "[deploy] storage-${KEY} démarré (réseau dc-${SITE}-lan)."
echo "[deploy] rappel : le 2e nœud de ce DC doit rejoindre CE MÊME réseau (voir README, macvlan si serveur physique séparé)."
