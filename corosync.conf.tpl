totem {
    version: 2
    cluster_name: storage-${SITE}
    transport: udpu
    crypto_cipher: none
    crypto_hash: none
    token: 3000
}

nodelist {
    node {
        ring0_addr: ${SELF_IP}
        nodeid: ${SELF_ID}
        name: ${SELF_NAME}
    }
    node {
        ring0_addr: ${PEER_IP}
        nodeid: ${PEER_ID}
        name: ${PEER_NAME}
    }
}

quorum {
    provider: corosync_votequorum
    two_node: 1
    wait_for_all: 1
}

logging {
    to_stderr: yes
    to_logfile: yes
    logfile: /var/log/corosync/corosync.log
    to_syslog: no
    timestamp: on
}
