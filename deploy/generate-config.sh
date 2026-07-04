#!/bin/bash
# storage-lucien/deploy/generate-config.sh — .env d'un nœud storage pour un
# déploiement réel (un serveur = un nœud du DC ; chaque DC a exactement 2
# nœuds, cf. design du repo).
#
# Usage:
#   ./generate-config.sh --site grenoble --node-id 1 --vip 10.20.1.19 \
#       --etcd-url http://10.20.1.5:2379 [--wg-gateway-ip 10.20.1.100]
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

SITE=""; STORAGE_ID=""; STORAGE_VIP=""; ETCD_URL=""; WG_GATEWAY_IP=""

while [ $# -gt 0 ]; do
    case "$1" in
        --site) SITE="$2"; shift 2 ;;
        --node-id) STORAGE_ID="$2"; shift 2 ;;
        --vip) STORAGE_VIP="$2"; shift 2 ;;
        --etcd-url) ETCD_URL="$2"; shift 2 ;;
        --wg-gateway-ip) WG_GATEWAY_IP="$2"; shift 2 ;;
        *) echo "unknown arg: $1" >&2; exit 1 ;;
    esac
done

[ -n "$SITE" ] || { echo "--site is required" >&2; exit 1; }
[ -n "$STORAGE_ID" ] || { echo "--node-id is required (1 ou 2)" >&2; exit 1; }
[ -n "$STORAGE_VIP" ] || { echo "--vip is required (identique pour les 2 nœuds du DC)" >&2; exit 1; }
[ -n "$ETCD_URL" ] || { echo "--etcd-url is required" >&2; exit 1; }
case "$STORAGE_ID" in 1|2) ;; *) echo "--node-id must be 1 or 2" >&2; exit 1 ;; esac

OUT_DIR="sites/${SITE}-${STORAGE_ID}"
mkdir -p "$OUT_DIR"

cat > "${OUT_DIR}/.env" <<EOF
SITE=${SITE}
STORAGE_ID=${STORAGE_ID}
STORAGE_VIP=${STORAGE_VIP}
ETCD_URL=${ETCD_URL}
WG_GATEWAY_IP=${WG_GATEWAY_IP}
EOF

echo "[generate-config] écrit ${OUT_DIR}/.env"
echo "[generate-config] à copier sur le serveur destiné à ce nœud, puis : ./deploy.sh ${SITE}-${STORAGE_ID}"
echo "[generate-config] rappel : les 2 nœuds d'un même DC doivent être sur le même réseau local que STORAGE_VIP (${STORAGE_VIP%.*}.0/24)."
