#!/bin/bash
# Pushes the Pacemaker CIB once the 2-node corosync cluster is quorate.
# Only manages ONE resource: the floating VIP (ocf:heartbeat:IPaddr2).
#
# Why only the VIP is Pacemaker-managed, not the GlusterFS mount/NFS-Ganesha
# export themselves: the GlusterFS replica-2 volume is mounted and NFS-Ganesha
# is running on BOTH nodes at all times (started directly by entrypoint.sh,
# outside Pacemaker) because GlusterFS already keeps both nodes' data
# consistent continuously. Pacemaker only has to decide which of the two
# already-ready nodes receives client traffic -> moving a single VIP is a
# much smaller, more reliable failure surface in a 2-node containerized lab
# cluster than trying to make Pacemaker manage a FUSE mount + a userspace
# NFS server via OCF/systemd resource agents (fragile in containers,
# especially the mount/unmount step).
#
# Known simulation limitation (documented, not a production design): a real
# 2-node Pacemaker cluster needs STONITH fencing to be split-brain safe.
# There is no real fencing hardware available inside Docker, so this cluster
# runs with stonith-enabled=false and relies on corosync's two_node/
# wait_for_all quorum behaviour only. Acceptable for demonstrating the HA
# mechanism; NOT how you would run this in production.
set -euo pipefail

VIP="$1"
CIDR="${2:-24}"
NIC="${3:-eth0}"

echo "[pacemaker] Waiting for cluster to be quorate..."
for i in $(seq 1 60); do
    if crm_mon -1 --as-xml 2>/dev/null | grep -q 'quorum="true"'; then
        break
    fi
    sleep 2
done

if ! crm_mon -1 --as-xml 2>/dev/null | grep -q 'quorum="true"'; then
    echo "[pacemaker] WARNING: cluster never reached quorum, configuring anyway"
fi

if cibadmin -Q 2>/dev/null | grep -q 'id="p_vip"'; then
    echo "[pacemaker] p_vip already configured, skipping"
    exit 0
fi

echo "[pacemaker] Configuring cluster properties + floating VIP ${VIP}/${CIDR} on ${NIC}"

# Pushed directly via cibadmin/crm_attribute rather than the crmsh "crm configure"
# REPL: crmsh 4.4.1 (Debian bookworm) hits a packaging bug on its diff-based
# commit path (NameError: cibadmin_opt) — cibadmin/crm_attribute are the
# lower-level, scriptable tools that pacemaker-cli-utils ships and don't go
# through that broken code path.
crm_attribute --type crm_config --name stonith-enabled --update false
crm_attribute --type crm_config --name no-quorum-policy --update ignore
crm_attribute --type rsc_defaults --name resource-stickiness --update 100

cibadmin --create --scope resources --xml-text "
<primitive id=\"p_vip\" class=\"ocf\" provider=\"heartbeat\" type=\"IPaddr2\">
  <instance_attributes id=\"p_vip-instance_attributes\">
    <nvpair id=\"p_vip-ip\" name=\"ip\" value=\"${VIP}\"/>
    <nvpair id=\"p_vip-cidr\" name=\"cidr_netmask\" value=\"${CIDR}\"/>
    <nvpair id=\"p_vip-nic\" name=\"nic\" value=\"${NIC}\"/>
  </instance_attributes>
  <operations>
    <op id=\"p_vip-monitor\" name=\"monitor\" interval=\"5s\" timeout=\"20s\"/>
    <op id=\"p_vip-start\" name=\"start\" interval=\"0s\" timeout=\"20s\"/>
    <op id=\"p_vip-stop\" name=\"stop\" interval=\"0s\" timeout=\"20s\"/>
  </operations>
</primitive>"

echo "[pacemaker] Done"
