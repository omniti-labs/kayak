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
# Copyright 2013 by Andrzej Szeszo. All rights reserved.
#
# Copyright 2013 OmniTI Computer Consulting, Inc.  All rights reserved.
# Use is subject to license terms.
#

log() {
    echo "$*"
}

SetupPart() {

    log "Setting up partition table on /dev/rdsk/${DISK}p0" 

    cat <<EOF | fdisk -F /dev/stdin /dev/rdsk/${DISK}p0
0 0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0 0
EOF

    #NUMSECT=`fdisk -G /dev/rdsk/${DISK}p0|awk '!/^\*/ { print $1 * $5 * $6 - 34816 }'`
    NUMSECT=`iostat -En $DISK|nawk '/^Size:/ { sub("<",""); print $3/512 - 34816 }'`

    fdisk -A 6:0:0:0:0:0:0:0:2048:32768 /dev/rdsk/${DISK}p0
    fdisk -A 191:0:0:0:0:0:0:0:34816:$NUMSECT /dev/rdsk/${DISK}p0
}

SetupPVGrub() {

    log "Setting up 16MB FAT16 pv-grub filesystem"

    echo y|mkfs -F pcfs -o b=pv-grub /dev/rdsk/${DISK}p0:c
    mount -F pcfs /dev/dsk/${DISK}p1 $ALTROOT
    cp $PVGRUB $ALTROOT/pv-grub.gz
    mkdir -p $ALTROOT/boot/grub

    cat <<EOF >$ALTROOT/boot/grub/menu.lst
timeout 0
default 0
title chainload pv-grub
root (hd0,0)
kernel /pv-grub.gz (hd0,1,a)/boot/grub/menu.lst
EOF

    umount $ALTROOT
}

SetupZPool() {

    log "Setting up '${RPOOL}' zpool"

    # some of the commands below were borrowed from disk_help.sh

    prtvtoc -h /dev/rdsk/${DISK}p0 | \
    awk '/./{p=0;} {if($1=="2"){size=$5;p=1;} if($1=="8"){start=$5;p=1;} if(p==1){print $1" "$2" "$3" "$4" "$5;}} END{size=size-start; print "0 2 00 "start" "size;}' | \
    sort -n | fmthard -s /dev/stdin /dev/rdsk/${DISK}s2 >/dev/null

    zpool create -f ${RPOOL} /dev/dsk/${DISK}s0

    zfs set compression=on ${RPOOL}
    zfs create ${RPOOL}/ROOT
#    zfs set canmount=off ${RPOOL}/ROOT
    zfs set mountpoint=legacy ${RPOOL}/ROOT
}

ZFSRecvBE() {
    log "Receiving ${RPOOL}/ROOT/${BENAME} filesystem"
    cat $ZFSSEND | pv -B 128m | bzip2 -dc | zfs receive -u ${RPOOL}/ROOT/${BENAME}
    zfs set canmount=noauto ${RPOOL}/ROOT/${BENAME}
    zfs set mountpoint=legacy ${RPOOL}/ROOT/${BENAME}
    zfs destroy ${RPOOL}/ROOT/${BENAME}@kayak || true
}

MountBE() {
    log "Mounting BE"
    mount -F zfs ${RPOOL}/ROOT/${BENAME} $ALTROOT
}

UmountBE() {
    log "Unmounting BE"
    umount $ALTROOT
}

PrepareBE() {

    log "Preparing BE"

    cp $ALTROOT/lib/svc/seed/global.db $ALTROOT/etc/svc/repository.db
    chmod 0600 $ALTROOT/etc/svc/repository.db
    chown root:sys $ALTROOT/etc/svc/repository.db

    /usr/sbin/devfsadm -r $ALTROOT

    [[ -L $ALTROOT/dev/msglog ]] || \
    ln -s ../devices/pseudo/sysmsg@0:msglog $ALTROOT/dev/msglog

    # GRUB stuff
    log "...setting up GRUB and the BE"
    mkdir -p /${RPOOL}/boot/grub/bootsign
    touch /${RPOOL}/boot/grub/bootsign/pool_${RPOOL}
    chown -R root:root /${RPOOL}/boot
    chmod 444 /${RPOOL}/boot/grub/bootsign/pool_${RPOOL}

    RELEASE=`head -1 $ALTROOT/etc/release | sed -e 's/ *//;'`

    cat <<EOF >/${RPOOL}/boot/grub/menu.lst
default 0
timeout 3

title ${BENAME}
findroot (pool_${RPOOL},1,a)
bootfs ${RPOOL}/ROOT/${BENAME}
kernel$ /platform/i86pc/kernel/amd64/unix -B \$ZFS-BOOTFS
module$ /platform/i86pc/amd64/boot_archive
#============ End of LIBBE entry =============
EOF

    sed -i -e "s/^title.*/title $RELEASE/;" /${RPOOL}/boot/grub/menu.lst

    bootadm update-archive -R $ALTROOT

    zpool set bootfs=${RPOOL}/ROOT/${BENAME} ${RPOOL}

    # Allow root to ssh in
    log "...setting PermitRootLogin=yes in sshd_config"
    sed -i -e 's%^PermitRootLogin.*%PermitRootLogin yes%' $ALTROOT/etc/ssh/sshd_config
    
    # Prevent direct root non-RSA logins (passwd -N equivalent)
    log "...NP'ing root's password"
    sed -i -e 's/^root:\$.*:/root:NP:6445::::::/;' $ALTROOT/etc/shadow

    # Set up to use DNS (hello, this is the year 2013. I never really understood this)
    log "...enabling DNS resolution"
    cp $ALTROOT/etc/nsswitch.dns $ALTROOT/etc/nsswitch.conf

    # Install ec2-credential and ec2-api-tools packages
    log "...installing EC2 packages"
    pkg -R $ALTROOT install ec2-credential ec2-api-tools

}
