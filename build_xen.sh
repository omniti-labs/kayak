#!/bin/bash
#
# CDDL HEADER START
#
# The contents of this file are subject to the terms of the
# Common Development and Distribution License, Version 1.0 only
# (the "License").  You may not use this file except in compliance
# with the License.
#
# You can obtain a copy of the license at usr/src/OPENSOLARIS.LICENSE
# or http://www.opensolaris.org/os/licensing.
# See the License for the specific language governing permissions
# and limitations under the License.
#
# When distributing Covered Code, include this CDDL HEADER in each
# file and include the License file at usr/src/OPENSOLARIS.LICENSE.
# If applicable, add the following below this CDDL HEADER, with the
# fields enclosed by brackets "[]" replaced with your own identifying
# information: Portions Copyright [yyyy] [name of copyright owner]
#
# CDDL HEADER END
#
#
# Copyright 2013 OmniTI Computer Consulting, Inc.  All rights reserved.
# Use is subject to license terms.
#

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
