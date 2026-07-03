FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# glusterfs-server   : brique de stockage distribué (replica intra-DC + geo-rep inter-DC)
# nfs-ganesha(-gluster): export NFSv4 userspace du volume GlusterFS (pas de dépendance
#                        au module noyau nfsd de l'hôte -> reste 100% conteneur)
# pacemaker+corosync : cluster HA à 2 nœuds, pilote uniquement la VIP flottante
# resource-agents    : fournit l'agent OCF IPaddr2 utilisé par Pacemaker pour la VIP
# openssh-client/server: transport de la géo-réplication GlusterFS (clé dédiée générée
#                        au premier démarrage, jamais committée)
RUN apt-get update && apt-get install -y --no-install-recommends \
        glusterfs-server \
        nfs-ganesha nfs-ganesha-gluster \
        pacemaker corosync pacemaker-cli-utils \
        resource-agents \
        openssh-client openssh-server \
        curl jq iproute2 iputils-ping netcat-traditional \
        ca-certificates gettext-base rsync \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /export/mail /data/brick /var/run/sshd /etc/ganesha \
    && ssh-keygen -A

COPY entrypoint.sh /entrypoint.sh
COPY healthcheck.sh /healthcheck.sh
COPY pacemaker/configure-cluster.sh /opt/storage-lucien/configure-cluster.sh
COPY ganesha.conf.tpl /etc/ganesha/ganesha.conf.tpl
COPY corosync.conf.tpl /etc/corosync/corosync.conf.tpl
RUN chmod +x /entrypoint.sh /healthcheck.sh /opt/storage-lucien/configure-cluster.sh

# NFSv4, rpcbind (ganesha embeds its own), corosync, sshd (geo-rep)
EXPOSE 2049 111 5404/udp 5405/udp 22

HEALTHCHECK --interval=15s --timeout=5s --retries=5 CMD ["/healthcheck.sh"]

ENTRYPOINT ["/entrypoint.sh"]
