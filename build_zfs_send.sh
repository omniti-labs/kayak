#!/bin/bash

fail() {
  echo $*
  exit 1
}

ZROOT=rpool
OUT=
set -- `getopt d:o: $*`
for i in $*
do
  case $i in
    -d) ZROOT=$2; shift 2;;
    -o) OUT=$2; shift 2;;
    --) shift; break ;;
  esac
done

name=$1
if [[ -z "$name" ]]; then
  echo "$0 [-d zfsparent] [-o outputfile] <release_name>"
  exit
fi

MPR=`zfs get -H mountpoint $ZROOT | awk '{print $3}'`
if [[ -z "$OUT" ]]; then
  OUT=$MPR/kayak_$name.zfs.bz2
fi

zfs create $ZROOT/$name || fail "zfs create"
MP=`zfs get -H mountpoint $ZROOT/$name | awk '{print $3}'`

pkg image-create -F -a omnios=http://pkg.omniti.com/omnios/release $MP || fail "image-create"
pkg -R $MP install entire || fail "install entire"
zfs snapshot $ZROOT/$name@kayak || fail "snap"
zfs send $ZROOT/$name@kayak | bzip2 -9 > $OUT || fail "send/compress"
zfs destroy $ZROOT/$name@kayak || fail "could not remove snapshot"
zfs destroy $ZROOT/$name || fail "could not remove zfs filesystem"
