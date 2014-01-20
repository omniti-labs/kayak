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
# Copyright 2012 OmniTI Computer Consulting, Inc.  All rights reserved.
# Use is subject to license terms.
#
fail() {
	echo "ERROR: $*"
	exit 1
}

# NOTE --> The URL needs to be updated with every release.
# Change "bloody" to whatever release the current branch is.
PUBLISHER=omnios
: ${PKGURL:=http://pkg.omniti.com/omnios/bloody}
: ${GZIP_CMD:=gzip}
SRCDIR=$(dirname $0)
DIDWORK=0
BUILDNUM=${VERSION//r/}
if [[ ${SRCDIR:0:1} != "/" ]]; then
  SRCDIR=`pwd`/$SRCDIR
fi
if [[ -z "${1}" ]]; then
  echo "$0 <zfs pool> [checkpoint]"
  exit 1
else
  BASE=${1}
  shift
  BASEDIR=`zfs get -o value -H mountpoint $BASE`
fi
MKFILEDIR=/tmp
WORKDIR=$BASEDIR
ROOTDIR=$WORKDIR/root
if [[ ! -d $ROOTDIR ]]; then
  zfs create -o compression=off $BASE/root || fail "zfs create failed"
fi
SVCCFG_DTD=${ROOTDIR}/usr/share/lib/xml/dtd/service_bundle.dtd.1
SVCCFG_REPOSITORY=${ROOTDIR}/etc/svc/repository.db
SVCCFG=/usr/sbin/svccfg
export WORKDIR ROOTDIR SVCCFG_DTD SVCCFG_REPOSITORY SVCCFG

# This was uber-helpful
# http://alexeremin.blogspot.com/2008/12/preparing-small-miniroot-with-zfs-and.html

PKG=/bin/pkg

UNNEEDED_MANIFESTS="application/management/net-snmp.xml
	application/pkg/pkg-server.xml application/pkg/pkg-mdns.xml
	system/rmtmpfiles.xml system/mdmonitor.xml
	system/fm/notify-params.xml system/device/allocate.xml
	system/device/devices-audio.xml system/auditd.xml
	system/metasync.xml system/pkgserv.xml system/fcoe_initiator.xml
	system/metainit.xml system/zonestat.xml
	system/cron.xml system/rbac.xml system/sac.xml
	system/auditset.xml system/hotplug.xml
	system/wusb.xml system/zones.xml
	system/intrd.xml system/coreadm.xml
	system/extended-accounting.xml
	system/scheduler.xml
	system/logadm-upgrade.xml system/resource-mgmt.xml
	system/idmap.xml
	network/ldap/client.xml network/shares/reparsed.xml
	network/shares/group.xml network/inetd-upgrade.xml
	network/smb/client.xml network/smb/server.xml
	network/network-iptun.xml network/ipsec/policy.xml
	network/ipsec/ipsecalgs.xml network/ipsec/ike.xml
	network/ipsec/manual-key.xml network/forwarding.xml
	network/inetd.xml network/npiv_config.xml
	network/ssl/kssl-proxy.xml network/rpc/metamed.xml
	network/rpc/mdcomm.xml network/rpc/gss.xml
	network/rpc/bind.xml network/rpc/keyserv.xml
	network/rpc/meta.xml network/rpc/metamh.xml
	network/socket-filter-kssl.xml network/network-netcfg.xml
	network/nfs/status.xml network/nfs/cbd.xml
	network/nfs/nlockmgr.xml network/nfs/mapid.xml
	network/nfs/client.xml network/network-ipqos.xml
	network/security/ktkt_warn.xml network/security/krb5kdc.xml
	network/security/kadmin.xml network/network-install.xml
	network/bridge.xml network/network-initial.xml
	network/network-ipmgmt.xml network/routing/legacy-routing.xml
	network/network-service.xml network/network-physical.xml
	network/network-netmask.xml network/dlmgmt.xml
	network/network-location.xml network/ibd-post-upgrade.xml
	network/network-routing-setup.xml network/network-loopback.xml
	network/dns/client.xml network/dns/install.xml
	network/dns/multicast.xml platform/i86pc/acpihpd.xml
	system/hostid.xml system/power.xml system/pfexecd.xml
	system/consadm.xml system/pools.xml system/console-login.xml
	system/stmf.xml system/fmd.xml system/utmp.xml
	system/poold.xml system/dumpadm.xml"

SYSTEM="system/boot/grub system/boot/real-mode system/boot/wanboot/internal
	system/boot/wanboot system/data/hardware-registry
	system/data/keyboard/keytables system/data/terminfo
	system/data/zoneinfo system/extended-system-utilities
	system/file-system/autofs system/file-system/nfs
	system/file-system/smb system/file-system/udfs
	system/file-system/zfs system/flash/fwflash
	system/fru-id/platform system/fru-id system/ipc
	system/kernel/dynamic-reconfiguration/i86pc
	system/kernel/security/gss system/library/math
	system/library/platform system/library/policykit
	system/library/processor
	system/library/storage/fibre-channel/hbaapi
	system/library/storage/fibre-channel/libsun_fc
	system/library/storage/ima/header-ima
	system/library/storage/ima
	system/library/storage/libmpapi
	system/library/storage/libmpscsi_vhci
	system/library/storage/scsi-plugins
	system/library system/network
	system/prerequisite/gnu system/storage/luxadm
	system/storage/fibre-channel/port-utility"

DEBUG_PKGS="developer/debug/mdb system/dtrace developer/dtrace"

DRIVERS="driver/audio driver/crypto/dca driver/crypto/tpm driver/firewire
	driver/graphics/agpgart driver/graphics/atiatom driver/graphics/drm
	driver/i86pc/fipe driver/i86pc/ioat driver/i86pc/platform
	driver/network/afe driver/network/amd8111s driver/network/atge
	driver/network/bfe driver/network/bge driver/network/bnx
	driver/network/bnxe driver/network/bpf driver/network/chxge
	driver/network/dmfe driver/network/e1000g driver/network/elxl
	driver/network/emlxs driver/network/eoib driver/network/fcip
	driver/network/fcp driver/network/fcsm driver/network/fp
	driver/network/hermon driver/network/hme driver/network/hxge
	driver/network/ib driver/network/ibdma driver/network/ibp
	driver/network/igb driver/network/iprb driver/network/ixgb
	driver/network/ixgbe driver/network/mxfe driver/network/myri10ge
	driver/network/nge driver/network/ntxn driver/network/nxge
	driver/network/ofk driver/network/pcn driver/network/platform
	driver/network/qlc driver/network/rds driver/network/rdsv3
	driver/network/rge driver/network/rpcib driver/network/rtls
	driver/network/sdp driver/network/sdpib driver/network/sfe
	driver/network/tavor driver/network/usbecm driver/network/vr
	driver/network/xge driver/network/yge driver/pcmcia driver/serial/pcser
	driver/serial/usbftdi driver/serial/usbsacm driver/serial/usbser
	driver/serial/usbser_edge driver/serial/usbsksp
	driver/serial/usbsksp/usbs49_fw driver/serial/usbsprl
	driver/storage/aac driver/storage/adpu320 driver/storage/ahci
	driver/storage/amr driver/storage/arcmsr driver/storage/ata
	driver/storage/bcm_sata driver/storage/blkdev driver/storage/cpqary3
	driver/storage/glm driver/storage/lsimega driver/storage/marvell88sx
	driver/storage/mega_sas driver/storage/mpt_sas driver/storage/mr_sas
	driver/storage/nv_sata driver/storage/pcata driver/storage/pmcs
	driver/storage/sbp2 driver/storage/scsa1394 driver/storage/sdcard
	driver/storage/ses driver/storage/si3124 driver/storage/smp
	driver/usb driver/usb/ugen driver/xvm/pv"

PARTS="release/name release/notices service/picl install/beadm SUNWcs SUNWcsd
	library/libidn shell/pipe-viewer text/less /network/ssh editor/vim
        developer/linker file/gnu-coreutils"

PKGS="$PARTS $SYSTEM $DRIVERS"

if [ -n "$DEBUG" ]; then
	PKGS="$PKGS $DEBUG_PKGS"
	BIGROOT=1
fi
CULL="perl python package/pkg snmp"
RMRF="/var/pkg /usr/share/man /usr/lib/python2.6 /usr/lib/iconv"

ID=`id -u`
if [[ "$ID" != "0" ]]; then
	echo "must run as root"
	exit 1
fi

chkpt() {
	SNAP=`zfs list -H -t snapshot $BASE/root@${1} 2> /dev/null`
	if [[ "$DIDWORK" -ne "0" ]]; then
		if [[ -n "$SNAP" ]]; then
			zfs destroy $BASE/root@${1} || \
				fail "zfs destroy ${1} failed"
		fi
		zfs snapshot $BASE/root@${1} || fail "zfs snapshot failed"
	fi
	if [[ "${1}" != "begin" ]]; then
		echo " === Proceeding to phase $1 (zfs @${1}) ==="
		zfs rollback -r $BASE/root@${1} || fail "zfs rollback failed"
	else
		echo " === Proceeding to phase $1 ==="
	fi
	CHKPT=$1
	DIDWORK=1
}

if [[ -n "$1" ]]; then
	echo "Explicit checkpoint requested: '$1'"
	CHKPT=$1
	chkpt $CHKPT
fi
if [[ -z "$CHKPT" ]]; then
	CHKPT="begin"
fi

declare -A keep_list
load_keep_list() {
	for datafile in $*
	do
		FCNT=0
		while read file
		do
			if [[ -n "$file" ]]; then
				keep_list+=([$file]="x")
				FCNT=$(($FCNT + 1))
			fi
		done < <(cut -f2- -d/ $datafile)
		echo " --- keeping $FCNT files from $datafile"
	done
}

step() {
	CHKPT=""
	case "$1" in

	"begin")
	zfs destroy -r $BASE/root 2> /dev/null
	zfs create -o compression=off $BASE/root || fail "zfs create failed"
	chkpt pkg
	;;

	"pkg")

	echo "Creating image of $PUBLISHER from $PKGURL"
	$PKG image-create -F -a $PUBLISHER=$PKGURL $ROOTDIR || fail "image-create"
        # If a version was requested, respect it
	if [[ -n $BUILDNUM ]]; then
		$PKG -R $ROOTDIR install illumos-gate@11-0.$BUILDNUM omnios-userland@11-0.$BUILDNUM || fail "version constraint prep"
	fi
	$PKG -R $ROOTDIR install $PKGS || fail "install"
	if [[ -n $BUILDNUM ]]; then
		$PKG -R $ROOTDIR uninstall illumos-gate omnios-userland || fail "version constraint cleanup"
	fi
	chkpt fixup
	;;

	"fixup")

	echo "Fixing up install root"
	(cp $ROOTDIR/etc/vfstab $WORKDIR/vfstab && \
		awk '{if($3!="/"){print;}}' $WORKDIR/vfstab > $ROOTDIR/etc/vfstab && \
		echo "/devices/ramdisk:a - / ufs - no nologging" >> $ROOTDIR/etc/vfstab) || \
		fail "vfstab / updated"
	rm $WORKDIR/vfstab
	cp $ROOTDIR/lib/svc/seed/global.db $ROOTDIR/etc/svc/repository.db

	sed -i 's,PASSREQ=YES,PASSREQ=NO,' $ROOTDIR/etc/default/login

	${SVCCFG} import ${ROOTDIR}/lib/svc/manifest/milestone/sysconfig.xml
	for xml in $UNNEEDED_MANIFESTS; do
		rm -f ${ROOTDIR}/lib/svc/manifest/$xml && echo " --- tossing $xml"
	done
	echo " --- initial manifest import"
	${ROOTDIR}/lib/svc/method/manifest-import -f ${ROOTDIR}/etc/svc/repository.db \
		-d ${ROOTDIR}/lib/svc/manifest

	${SVCCFG} -s 'system/boot-archive' setprop 'start/exec=:true'
	${SVCCFG} -s 'system/manifest-import' setprop 'start/exec=:true'
	${SVCCFG} -s "system/intrd:default" setprop "general/enabled=false"
	${SVCCFG} -s "system/initial-boot" setprop "start/timeout_seconds=600"
	echo " --- nuetering the manifest import"
        echo "#!/bin/ksh" > ${ROOTDIR}/lib/svc/method/manifest-import
        echo "exit 0" >> ${ROOTDIR}/lib/svc/method/manifest-import
	chmod 555 ${ROOTDIR}/lib/svc/method/manifest-import
	chkpt cull
	;;

	"cull")
	if [[ -z "$BIGROOT" ]]; then
		load_keep_list data/*
		while read file
		do
			if [[ -n "$file" && \
			      ${keep_list[$file]} == "" && \
			      -e "$ROOTDIR/$file" && \
			      ! -d $ROOTDIR/$file ]] ; then
				rm -f $ROOTDIR/$file
			fi
		done < <(cd $ROOTDIR && find ./ | cut -c3-)
		for path in $RMRF ; do
			rm -rf ${ROOTDIR}$path && echo " -- tossing $path"	
		done
	fi

	chkpt mkfs
	;;

	"mkfs")
	size=`/usr/bin/du -ks ${ROOTDIR}|/usr/bin/nawk '{print $1+10240}'`
	echo " --- making image of size $size"
	/usr/sbin/mkfile ${size}k $MKFILEDIR/miniroot || fail "mkfile"
	lofidev=`/usr/sbin/lofiadm -a $MKFILEDIR/miniroot`
	rlofidev=`echo $lofidev |sed s/lofi/rlofi/`
	yes | /usr/sbin/newfs -m 0 $rlofidev 2> /dev/null > /dev/null || fail "newfs"
	chkpt mount
	;;

	"mount")
	mkdir -p $WORKDIR/mnt
	/usr/sbin/mount -o nologging $lofidev $WORKDIR/mnt || fail "mount"
	chkpt copy
	;;

	"copy")
	pushd $ROOTDIR >/dev/null
	/usr/bin/find . | /usr/bin/cpio -pdum $WORKDIR/mnt 2> /dev/null > /dev/null || fail "populate root"
	/usr/sbin/devfsadm -r $WORKDIR/mnt > /dev/null
	popd >/dev/null
	mkdir $WORKDIR/mnt/kayak
	cp $SRCDIR/*.sh $WORKDIR/mnt/kayak/
	chmod a+x $WORKDIR/mnt/kayak/*.sh
	make_initial_boot $WORKDIR/mnt/.initialboot
	if [[ -n "$DEBUG" ]]; then
		cp $SRCDIR/anon.system $WORKDIR/mnt/etc/system
		cp $SRCDIR/anon.dtrace.conf $WORKDIR/mnt/kernel/drv/dtrace.conf
	fi
	chkpt umount
	;;

	"umount")
	/usr/sbin/umount $WORKDIR/mnt || fail "umount"
	/usr/sbin/lofiadm -d $MKFILEDIR/miniroot || fail "lofiadm delete"
	chkpt compress
	;;

	"compress")
	$GZIP_CMD -c -f $MKFILEDIR/miniroot > $WORKDIR/miniroot.gz
	rm -f $MKFILEDIR/miniroot
	chmod 644 $WORKDIR/miniroot.gz
	echo " === Finished ==="
	ls -l $WORKDIR/miniroot.gz
	;;

	esac
}

make_initial_boot() {
FILE=$1
cat > $FILE <<EOF
	/kayak/install_image.sh
	exit \$?
EOF
}

while [[ -n "$CHKPT" ]]; do
	step $CHKPT
done
