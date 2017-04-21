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

RPOOL=${1:-rpool}
ZFS_IMAGE=/root/*.zfs.bz2
keyboard_layout=${2:-US-English}

zpool list $RPOOL >& /dev/null
if [[ $? != 0 ]]; then
   echo "Cannot find root pool $RPOOL"
   echo "Press RETURN to exit"
   read
   exit 1
fi

echo "Installing from ZFS image $ZFS_IMAGE"


. /kayak/disk_help.sh
. /kayak/install_help.sh

reality_check() {
    # Make sure $1 (hostname) is a legit one.
    echo $1 | egrep '^[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9]$' > /dev/null
    if [[ $? != 0 ]]; then
        echo "[$1] is not a legitimate hostname."
        return -1
    fi
    return 0
}

# Select a host name
NEWHOST="unknown"
until [[ $NEWHOST == "" ]]; do
    HOSTNAME=$NEWHOST
    echo -n "Please enter a hostname or press RETURN if you want [$HOSTNAME]: "
    read NEWHOST
    if [[ $NEWHOST != "" ]]; then
	reality_check $NEWHOST
	if [[ $? != 0 ]]; then
	    NEWHOST=$HOSTNAME
	fi
    fi
done

# Select a timezone.
tzselect |& tee /tmp/tz.$$
TZ=$(tail -1 /tmp/tz.$$)
rm -f /tmp/tz.$$

# Because of kayak's small miniroot, just use C as the language for now.
LANG=C

BuildBE $RPOOL $ZFS_IMAGE
ApplyChanges $HOSTNAME $TZ $LANG $keyboard_layout
MakeBootable $RPOOL
zpool list -v $RPOOL
echo ""
beadm list
echo ""
echo "$RPOOL now has a working and mounted boot environment, per above."
echo "Once back at the main menu, you can reboot from there, or"
echo "re-enter the shell to modify your new BE before its first boot."
echo -n "Press RETURN to go back to the menu: "
read
