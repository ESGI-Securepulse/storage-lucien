# NFS-Ganesha export of the local GlusterFS FUSE mount (/export/mail).
# FSAL_VFS on top of the FUSE mount (not FSAL_GLUSTER/libgfapi) on purpose:
# simpler, no extra client library coupling, and the consistency guarantee
# already comes from GlusterFS's own replica-2 volume underneath.
NFS_CORE_PARAM {
    Enable_NLM = false;
    Enable_RQUOTA = false;
    mount_path_pseudo = true;
    Protocols = 4;
}

NFSv4 {
    Grace_Period = 5;
    Lease_Lifetime = 5;
    Minor_Versions = 1,2;
}

EXPORT {
    Export_Id = 1;
    Path = /export/mail;
    Pseudo = /mail;
    Access_Type = RW;
    Squash = No_root_squash;
    SecType = sys;
    Protocols = 4;
    Transports = TCP;

    FSAL {
        Name = VFS;
    }
}

LOG {
    Default_Log_Level = EVENT;
}
