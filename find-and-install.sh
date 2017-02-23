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

# Capture diskinfo(1M) output in a tempfile.

keyboard_layout=${1:-US-English}
SCRATCH=/tmp/di.$$
diskinfo > $SCRATCH
numdisks=`wc -l $SCRATCH | awk '{print $1}'`
echo "numdisks before $numdisks"
numdisks=$(($numdisks - 1))
echo "numdisks after $numdisks"

# Number of disks on one page, must be <= 7.
onepage=7
highpage=$(($numdisks / $onepage))
remainder=$(($numdisks % $onepage))
if [[ $remainder != 0 ]]; then
    highpage=$(($highpage + 1))
fi

# Present the list of disks in a pretty manner, and get the user to
# generate a list of one or more disks.  Put them in $DISKLIST...
finished=0
offset=2
page=0
DISKLIST=""
until [[ $finished == 1 ]]; do
    clear
    echo "root pool disks: [$DISKLIST]"
    echo "0 == done, 1-7 == select-disk 8 == next-page, 9 == clear"
    echo "--------------------------------------------------------"
    head -1 $SCRATCH | awk '{print "#   ",$0}'
    echo ""
    tail +$offset $SCRATCH | head -$onepage | awk '{print NR,"   ",$0}' \
						  > /tmp/dp.$$
    cat /tmp/dp.$$
    echo ""
    echo -n "Enter a digit or the disk device name ==> "
    read choice

    if [[ $choice == 9 ]]; then
	DISKLIST=""
    elif [[ $choice == 8 ]]; then
	page=$(($page + 1))
	if [[ $page == $highpage ]]; then
	    page=0
	fi
	offset=$(($page * $onepage + 2))
    elif [[ $choice == 0 ]]; then
	if [[ $DISKLIST == "" ]]; then
	    echo -n "Press RETURN to go back to the main menu: "
	    read
	    exit
	else
	    finished=1
	fi
    else
	if [[ $choice == "" ]]; then
	    continue
	fi
	NEWDISK=`nawk -v choice=$choice '$1 == choice {print $3}' < /tmp/dp.$$`
	if [[ $NEWDISK == "" ]]; then
	    NEWDISK=`nawk -v choice=$choice '$3 == choice {print $3}' < \
		/tmp/dp.$$`
	fi
	if [[ $NEWDISK != "" ]]; then
	    if [[ $DISKLIST == "" ]]; then
		DISKLIST=$NEWDISK
	    elif [[ `echo $DISKLIST | grep $NEWDISK` == "" ]]; then
		DISKLIST="$DISKLIST $NEWDISK"
	    fi
	fi
    fi
    rm /tmp/dp.$$
done


reality_check() {
    mkfile 64m /tmp/test.$$
    if [[ $? != 0 ]]; then
	echo "WARNING: Insufficient space in /tmp for installation..."
	return 1
    fi
    zpool create $1 /tmp/test.$$
    if [[ $? != 0 ]]; then
	echo "Can't test zpool create $1"
	return 1
    fi
    zpool destroy $1
    rm -f /tmp/test.$$
    return 0
}

NEWRPOOL="rpool"
until [[ $NEWRPOOL == "" ]]; do
    RPOOL=$NEWRPOOL
    echo -n "Enter the root pool name or press RETURN if you want [$RPOOL]: "
    read NEWRPOOL
    if [[ $NEWRPOOL != "" ]]; then
	reality_check $NEWRPOOL
	if [[ $? != 0 ]]; then
	    NEWRPOOL=$RPOOL
	fi
    fi
done

. /kayak/install_help.sh
. /kayak/disk_help.sh
BuildRpoolOnly $DISKLIST

rm -f $SCRATCH

# Running actual install.
/kayak/rpool-install.sh $RPOOL $keyboard_layout
