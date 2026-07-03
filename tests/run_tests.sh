#!/bin/bash
# storage-lucien — suite de tests d'intégration (2 sites x 2 nœuds).
# À exécuter après `docker compose -f docker-compose.test.yml up -d --build`.
set -uo pipefail

PASS=0
FAIL=0

ok()   { echo "  OK  - $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL- $1"; FAIL=$((FAIL+1)); }

section() { echo; echo "== $1 =="; }

wait_for() {
    local desc="$1" cmd="$2" tries="${3:-60}"
    for i in $(seq 1 "$tries"); do
        eval "$cmd" > /dev/null 2>&1 && return 0
        sleep 2
    done
    echo "  (timeout waiting for: $desc)"
    return 1
}

section "1. Cluster GlusterFS formé (site-a)"
wait_for "gluster peer connected" "docker exec sl-test-a1 gluster peer status | grep -qi 'Peer in Cluster'" 60 \
    && ok "site-a: peer connecté" || bad "site-a: peer non connecté"

section "2. Volume replica-2 démarré (site-a)"
wait_for "volume started" "docker exec sl-test-a1 gluster volume status gvol-site-a" 60 \
    && ok "site-a: volume gvol-site-a démarré" || bad "site-a: volume non démarré"

section "3. Montage NFS/FUSE local sur les 2 nœuds"
docker exec sl-test-a1 mountpoint -q /export/mail && ok "a1: /export/mail monté" || bad "a1: /export/mail non monté"
docker exec sl-test-a2 mountpoint -q /export/mail && ok "a2: /export/mail monté" || bad "a2: /export/mail non monté"

section "4. Réplication SYNCHRONE intra-DC (écriture a1 -> lecture a2)"
# La géo-réplication bidirectionnelle (test 9/10) marque transitoirement le
# volume en lecture seule avant qu'ensure_local_writable() (boucle de fond,
# cf. entrypoint.sh) ne le corrige — jusqu'à ~1 cycle de watch (30s). On
# retente l'écriture plutôt que d'échouer sur cette fenêtre de convergence
# attendue (cohérent avec la philosophie "pas d'instantanéité" du projet).
WRITE_OK=0
for i in $(seq 1 20); do
    if docker exec sl-test-a1 sh -c 'echo "sync-test-$(date +%s)" > /export/mail/sync_test.txt' 2>/dev/null; then
        WRITE_OK=1; break
    fi
    sleep 3
done
sleep 2
CONTENT_A1=$(docker exec sl-test-a1 cat /export/mail/sync_test.txt 2>/dev/null)
CONTENT_A2=$(docker exec sl-test-a2 cat /export/mail/sync_test.txt 2>/dev/null)
if [ "$WRITE_OK" = "1" ] && [ -n "$CONTENT_A1" ] && [ "$CONTENT_A1" = "$CONTENT_A2" ]; then
    ok "réplication sync intra-DC OK (contenu identique a1/a2, écriture après ${i}x3s)"
else
    bad "réplication sync intra-DC KO (a1='$CONTENT_A1' a2='$CONTENT_A2')"
fi

section "5. NFS-Ganesha répond (showmount)"
docker exec sl-test-a1 pidof ganesha.nfsd > /dev/null 2>&1 && ok "a1: ganesha.nfsd actif" || bad "a1: ganesha.nfsd absent"
docker exec sl-test-a2 pidof ganesha.nfsd > /dev/null 2>&1 && ok "a2: ganesha.nfsd actif" || bad "a2: ganesha.nfsd absent"

section "6. Corosync/Pacemaker quorum + VIP flottante (site-a)"
wait_for "pacemaker quorate" "docker exec sl-test-a1 crm_mon -1 --as-xml | grep -q 'quorum=\"true\"'" 40 \
    && ok "site-a: cluster Pacemaker quorate" || bad "site-a: cluster non quorate"

VIP_HOLDER=""
for c in sl-test-a1 sl-test-a2; do
    if docker exec "$c" ip addr show | grep -q "10.60.1.19"; then
        VIP_HOLDER="$c"
    fi
done
[ -n "$VIP_HOLDER" ] && ok "VIP 10.60.1.19 portée par ${VIP_HOLDER}" || bad "VIP 10.60.1.19 non assignée à aucun nœud"

section "7. Failover Pacemaker : arrêt du porteur de VIP"
if [ -n "$VIP_HOLDER" ]; then
    docker exec "$VIP_HOLDER" pkill -9 pacemakerd 2>/dev/null || true
    docker exec "$VIP_HOLDER" pkill -9 corosync 2>/dev/null || true
    SURVIVOR="sl-test-a1"; [ "$VIP_HOLDER" = "sl-test-a1" ] && SURVIVOR="sl-test-a2"
    MIGRATED=0
    for i in $(seq 1 30); do
        if docker exec "$SURVIVOR" ip addr show 2>/dev/null | grep -q "10.60.1.19"; then
            MIGRATED=1; break
        fi
        sleep 2
    done
    [ "$MIGRATED" = "1" ] && ok "VIP migrée vers ${SURVIVOR} après panne de ${VIP_HOLDER}" \
        || bad "VIP non migrée après panne de ${VIP_HOLDER} (limitation connue possible, cf README)"
else
    echo "  (skip: pas de porteur de VIP identifié à l'étape 6)"
fi

section "8. Registration etcd (découverte inter-briques)"
KEY_B64=$(printf '%s' "/skydns/fr/securepulse/all/storage/" | base64)
END_B64=$(printf '%s' "/skydns/fr/securepulse/all/storage0" | base64)
STORAGE_A=$(curl -s -X POST http://localhost:15379/v3/kv/range \
    -d "{\"key\":\"${KEY_B64}\",\"range_end\":\"${END_B64}\"}" 2>/dev/null)
echo "$STORAGE_A" | grep -q kvs && ok "storage VIPs enregistrées dans etcd (/skydns/.../all/storage/)" \
    || bad "aucune entrée etcd trouvée pour les VIPs storage"

section "9. Géo-réplication asynchrone inter-DC (site-a -> site-b)"
wait_for "georep session active" \
    "docker exec sl-test-a1 gluster volume geo-replication gvol-site-a status | grep -E 'Active|Passive'" 60 \
    && ok "session géo-réplication site-a -> site-b créée" \
    || bad "session géo-réplication non détectée (peut nécessiter plus de temps, cf logs)"

section "10. Propagation réelle des données (async, écriture a1 -> lecture site-b)"
MARKER="georep-e2e-$(date +%s)"
# Même fenêtre de convergence read-only que le test 4 : on retente l'écriture.
for i in $(seq 1 20); do
    docker exec sl-test-a1 sh -c "echo '${MARKER}' > /export/mail/georep_test.txt" 2>/dev/null && break
    sleep 3
done
PROPAGATED=0
for i in $(seq 1 20); do
    content=$(docker exec sl-test-b1 cat /export/mail/georep_test.txt 2>/dev/null)
    if [ "$content" = "$MARKER" ]; then PROPAGATED=1; break; fi
    sleep 2
done
[ "$PROPAGATED" = "1" ] && ok "écriture propagée de site-a vers site-b en <= $((i*2))s (asynchrone)" \
    || bad "écriture non propagée vers site-b dans le délai imparti"

echo
echo "===================================="
echo " Résultats: ${PASS} OK / ${FAIL} FAIL"
echo "===================================="
[ "$FAIL" -eq 0 ]
