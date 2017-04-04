#!/bin/bash
#
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


# Copyright 2017 OmniTI Computer Consulting, Inc.  All rights reserved.
#

fail() {
  echo $*
  exit 1
}

# NOTE --> The URL needs to be updated with every release.  
# Change "bloody" to whatever release the current branch is.
PUBLISHER=omnios
OMNIOS_URL=https://pkg.omniti.com/omnios/bloody
: ${PKGURL:=https://pkg.omniti.com/omnios/bloody}
: ${BZIP2:=bzip2}
ZROOT=rpool
OUT=
CLEANUP=0
set -- `getopt cd:o:p: $*`
for i in $*
do
  case $i in
    -c) CLEANUP=1; shift ;;
    -d) ZROOT=$2; shift 2;;
    -o) OUT=$2; shift 2;;
    -p) PROFILE=$2; shift 2;;
    -P) PUBLISHER_OVERRIDE=1; shift ;;
    --) shift; break ;;
  esac
done

name=$1
if [[ -z "$name" ]]; then
  echo "$0 [-cP] [-d zfsparent] [-p profile] [-o outputfile] <release_name>"
  exit
fi

MPR=`zfs get -H mountpoint $ZROOT | awk '{print $3}'`
if [[ -z "$OUT" ]]; then
  OUT=$MPR/kayak_$name.zfs.bz2
fi

if zfs list $ZROOT/$name@entire > /dev/null 2>&1; then
  zfs rollback -r $ZROOT/$name@entire
  MP=`zfs get -H mountpoint $ZROOT/$name | awk '{print $3}'`
else
  zfs create $ZROOT/$name || fail "zfs create"
  MP=`zfs get -H mountpoint $ZROOT/$name | awk '{print $3}'`
  pkg image-create -F -p $PUBLISHER=$PKGURL $MP || fail "image-create"
  # If r151006, use a specific version to avoid missing incorporation
  if [[ "$name" == "r151006" ]]; then
    entire_version="151006:20131210T224515Z"
  else
    entire_version=${name//r/}
  fi
  pkg -R $MP install entire@11-0.$entire_version openssh-server || fail "install entire"
  zfs snapshot $ZROOT/$name@entire
fi

if [[ -n "$PROFILE" ]]; then
  echo "Applying custom profile: $PROFILE"
  [[ -r "$PROFILE" ]] || fail "Cannot find file: $PROFILE"
  while read line ;
  do
    TMPPUB=`echo $line | cut -f1 -d=`
    TMPURL=`echo $line | cut -f2 -d=`
    if [[ -n "$TMPURL" && "$TMPURL" != "$TMPPUB" ]]; then
      echo "Setting publisher: $TMPPUB / $TMPURL"
      pkg -R $MP set-publisher -g $TMPURL $TMPPUB || fail "set publisher $TMPPUB"
      PUBLISHER=$TMPPUB
      PKGURL=$TMPURL
    else
      echo "Installing additional package: $line"
      pkg -R $MP install -g $PKGURL $line || fail "install $line"
    fi
  done < <(grep . $PROFILE | grep -v '^ *#')
fi

if [[ -n "$PUBLISHER_OVERRIDE" ]]; then
  OMNIOS_URL=$PKGURL
fi
echo "Setting omnios publisher to $OMNIOS_URL"
pkg -R $MP unset-publisher omnios
pkg -R $MP set-publisher -P --no-refresh -g $OMNIOS_URL omnios
# Starting with r151014, require signatures for the omnios publisher.
# NOTE:  Uncomment this line when you branch off a release.  "bloody" packages
# are unsigned, but release ones are, and we should require checking their
# signatures.
#pkg -R $MP set-publisher --set-property signature-policy=require-signatures omnios

zfs snapshot $ZROOT/$name@kayak || fail "snap"
zfs send $ZROOT/$name@kayak | $BZIP2 -9 > $OUT || fail "send/compress"
if [[ "$CLEANUP" -eq "1" ]]; then
  zfs destroy $ZROOT/$name@kayak || fail "could not remove snapshot"
  zfs destroy $ZROOT/$name || fail "could not remove zfs filesystem"
fi
