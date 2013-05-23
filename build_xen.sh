#!/bin/bash

[[ $(id -u) != 0 ]] && echo Please run this script as root && exit 1

. install_help.sh 2>/dev/null
. net_help.sh
. xen_help.sh

set -e

DISK=c0t2d0
ZFSSEND=/var/kayak/kayak/r151006.zfs.bz2
PVGRUB=pv-grub.gz.d3950d8

RPOOL=syspool
BENAME=omnios
ALTROOT=/mnt
UNIX=/platform/i86xpv/kernel/amd64/unix

zpool destroy $RPOOL 2>/dev/null || true

SetupPart
SetupPVGrub
SetupZPool
ZFSRecvBE

MountBE

# we need custom PV kernel because of this:
# https://www.illumos.org/issues/3172
if [[ -f $UNIX ]]; then
    cp $UNIX $ALTROOT/platform/i86xpv/kernel/amd64/unix
    chown root:sys $ALTROOT/platform/i86xpv/kernel/amd64/unix
fi

PrepareBE
ApplyChanges
SetTimezone UTC

Postboot '/sbin/ipadm create-if xnf0'
Postboot '/sbin/ipadm create-addr -T dhcp xnf0/v4'
Postboot 'for i in 0 1 2 3 4 5 6 7 8 9; do curl -f http://169.254.169.254/ >/dev/null 2>&1 && break; sleep 1; done'
Postboot 'HOSTNAME=$(/usr/bin/curl http://169.254.169.254/latest/meta-data/hostname)'
Postboot '[[ -z $HOSTNAME ]] || (/usr/bin/hostname $HOSTNAME && echo $HOSTNAME >/etc/nodename)'

UmountBE

zpool export ${RPOOL}
