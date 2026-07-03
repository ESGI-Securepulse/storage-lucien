#!/bin/bash
gluster peer status > /dev/null 2>&1 || exit 1
mountpoint -q /export/mail || exit 1
pidof ganesha.nfsd > /dev/null 2>&1 || exit 1
exit 0
