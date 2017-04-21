#!/usr/bin/bash

#
# This file and its contents are supplied under the terms of the
# Common Development and Distribution License ("CDDL"), version 1.0.
# You may only use this file in accordance with the terms of version
# 1.0 of the CDDL.
#
# A full copy of the text of the CDDL should have accompanied this
# source.  A copy of the CDDL is also available via the Internet at
# http://www.illumos.org/license/CDDL.
#

#
# Copyright 2017 OmniTI Computer Consulting, Inc. All rights reserved.
#

#
# Build an ISO installer using the Kayak tools.
#

if [[ `id -u` != "0" ]]; then
	echo "You must be root to run this script."
	exit 1
fi

if [[ -z $BUILDSEND_MP ]]; then
	echo "Using /rpool/kayak_image for BUILDSEND_MP"
	BUILDSEND_MP=/rpool/kayak_image
fi

if [[ -z $VERSION ]]; then
	VERSION=`grep OmniOS $BUILDSEND_MP/root/etc/release | awk '{print $3}'`
	echo "Using $VERSION..."
fi

# Many of these depend on sufficient space in /tmp by default.  Please
# modify as you deem appropriate.
PROTO=/tmp/proto
KAYAK_ROOTBALL=$BUILDSEND_MP/miniroot.gz
KAYAK_ROOT=/tmp/miniroot.$$
KR_FILE=/tmp/kr.$$
MNT=/mnt
UFS_LOFI=/tmp/boot_archive
LOFI_SIZE=600M
DST_ISO=$BUILDSEND_MP/${VERSION}.iso
ZFS_IMG=$BUILDSEND_MP/kayak_${VERSION}.zfs.bz2

# Create a UFS lofi file and mount the UFS filesystem in $MNT.  This will
# form the boot_archive for the ISO.
mkfile $LOFI_SIZE $UFS_LOFI
LOFI_PATH=`lofiadm -a $UFS_LOFI`
echo 'y' | newfs $LOFI_PATH
mount $LOFI_PATH $MNT

# Clone the already-created Kayak miniroot and copy it into both $MNT, and
# into a now-created $PROTO. $PROTO will form the directory that gets
# sprayed onto the ISO.
gunzip -c $KAYAK_ROOTBALL > $KR_FILE
LOFI_RPATH=`lofiadm -a $KR_FILE`
mkdir $KAYAK_ROOT
mount $LOFI_RPATH $KAYAK_ROOT
tar -cf - -C $KAYAK_ROOT . | tar -xf - -C $MNT
mkdir $PROTO
tar -cf - -C $KAYAK_ROOT . | tar -xf - -C $PROTO
umount $KAYAK_ROOT
rmdir $KAYAK_ROOT
lofiadm -d $LOFI_RPATH
rm $KR_FILE

#
# Put additional goodies into the boot-archive on $MNT, which is
# what'll be / (via ramdisk) once one boots the ISO.
# 

# The full ZFS image (also already-created) for actual installation.
cp $ZFS_IMG $MNT/root/.

# A cheesy way to get the boot menu to appear at boot time.
cp -p ./takeover-console $MNT/kayak/.
cat <<EOF > $MNT/root/.bashrc
export PATH=/usr/bin:/usr/sbin:/sbin
export HOME=/root
EOF
# Have initialboot make an interactive installer get invoked.
cat <<EOF > $MNT/.initialboot
# Adjust initial-boot's start timeout so the installer has plenty of time
# to interact and work.  An hour (3600 secs) seems okay.
if [[ \`svcprop -p start/timeout_seconds initial-boot\` != 3600 ]]; then
	svccfg -s system/initial-boot setprop "start/timeout_seconds=3600"
	svcadm refresh system/initial-boot
	. /.initialboot
else
	/kayak/takeover-console /kayak/kayak-menu.sh
fi
EOF

# Refresh the devices on the miniroot.
devfsadm -r $MNT

#
# The ISO's miniroot is going to be larger than the PXE miniroot.  To that
# end, some files not listed in the exception list do need to show up on
# the miniroot.  Use PREBUILT_ILLUMOS if available, or the current system
# if not.
#
from_one_to_other() {
    dir=$1
    if [[ -z $PREBUILT_ILLUMOS || ! -d $PREBUILT_ILLUMOS/proto/root_i386/$dir ]]
    then
	FROMDIR=/
    else
	FROMDIR=$PREBUILT_ILLUMOS/proto/root_i386
    fi

    shift
    tar -cf - -C $FROMDIR/$dir ${@:-.} | tar -xf - -C $MNT/$dir
}

# Add from_one_to_other for any directory {file|subdir file|subdir ...} you need
from_one_to_other usr/share/lib/zoneinfo
from_one_to_other usr/share/lib/keytables
from_one_to_other usr/share/lib/terminfo
from_one_to_other usr/gnu/share/terminfo
from_one_to_other usr/sbin ping
from_one_to_other usr/bin netstat

# Remind people this is the installer.
cat <<EOF > $PROTO/boot/loader.conf.local
loader_menu_title="Welcome to the OmniOS installer"
autoboot_delay=5
EOF

#
# Okay, we've populated the new ISO miniroot.  Close it up and install it
# on $PROTO as the boot archive.
#
umount $MNT
lofiadm -d $LOFI_PATH
cp $UFS_LOFI $PROTO/platform/i86pc/amd64/boot_archive
digest -a sha1 $UFS_LOFI > $PROTO/platform/i86pc/amd64/boot_archive.hash
rm -rf $PROTO/{usr,bin,sbin,lib,kernel}
du -sh $PROTO/.

# And finally, burn the ISO.
mkisofs -o $DST_ISO -b boot/cdboot -c .catalog -no-emul-boot -boot-load-size 4 -boot-info-table -N -l -R -U -allow-multidot -no-iso-translate -cache-inodes -d -D -V OmniOS $PROTO

rm -rf $PROTO $UFS_LOFI
echo "$DST_ISO is ready"
ls -lt $DST_ISO
