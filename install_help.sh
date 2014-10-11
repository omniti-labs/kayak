#!/usr/bin/bash
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
LOG_SETUP=0

ConsoleLog(){
  exec 4>/dev/console
  exec 1>>${1}
  exec 2>>${1}
  INSTALL_LOG=${1}
  LOG_SETUP=1
}
CopyInstallLog(){
  if [[ -n "$INSTALL_LOG" ]]; then
    cp $INSTALL_LOG $ALTROOT/var/log/install/kayak.log
  fi
}
SendInstallLog(){
  PUTURL=`echo $CONFIG | sed -e 's%/kayak/%/kayaklog/%g;'`
  PUTURL=`echo $PUTURL | sed -e 's%/kayak$%/kayaklog%g;'`
  curl -T $INSTALL_LOG $PUTURL/$ETHER
}
OutputLog(){
  if [[ "$LOG_SETUP" -eq "0" ]]; then
    exec 4>/dev/null
    LOG_SETUP=1
  fi
}
log() {
  OutputLog
  TS=`date +%Y/%m/%d-%H:%M:%S`
  echo "[$TS] $*" 1>&4
  echo "[$TS] $*"
}
bomb() {
  log
  log ======================================================
  log "$*"
  log ======================================================
  if [[ -n "$INSTALL_LOG" ]]; then
  log "For more information, check $INSTALL_LOG"
  log ======================================================
  fi
  exit 1
}

. /kayak/net_help.sh
. /kayak/disk_help.sh

ICFILE=/tmp/_install_config
getvar(){
  prtconf -v /devices | sed -n '/'$1'/{;n;p;}' | cut -f2 -d\'
}

# Blank
ROOTPW='$5$kr1VgdIt$OUiUAyZCDogH/uaxH71rMeQxvpDEY2yX.x0ZQRnmeb9'
RootPW(){
  ROOTPW="$1"
}
SetRootPW(){
  sed -i -e 's%^root::%root:'$ROOTPW':%' $ALTROOT/etc/shadow
}
ForceDHCP(){
  log "Forcing all interfaces into DHCP..."
  /sbin/ifconfig -a plumb 2> /dev/null
  # for the logs
  for iface in `/sbin/dladm show-phys -o device -p` ; do
    /sbin/ifconfig $iface dhcp &
  done
  while [[ -z $(/sbin/dhcpinfo BootSrvA) ]]; do
    log "Waiting for dhcpinfo..."
    sleep 1
  done
  BOOTSRVA=`/sbin/dhcpinfo BootSrvA`
  log "Next server: $BOOTSRVA"
  sleep 1
}

BuildBE() {
  BOOTSRVA=`/sbin/dhcpinfo BootSrvA`
  MEDIA=`getvar install_media`
  MEDIA=`echo $MEDIA | sed -e "s%//\:%//$BOOTSRVA\:%g;"`
  MEDIA=`echo $MEDIA | sed -e "s%///%//$BOOTSRVA/%g;"`
  zfs set compression=on rpool
  zfs create rpool/ROOT
  zfs set canmount=off rpool/ROOT
  zfs set mountpoint=legacy rpool/ROOT
  log "Receiving image: $MEDIA"
  curl -s $MEDIA | pv -B 128m | bzip2 -dc | zfs receive -u rpool/ROOT/omnios
  zfs set canmount=noauto rpool/ROOT/omnios
  zfs set mountpoint=legacy rpool/ROOT/omnios
  log "Cleaning up boot environment"
  beadm mount omnios /mnt
  ALTROOT=/mnt
  cp $ALTROOT/lib/svc/seed/global.db $ALTROOT/etc/svc/repository.db
  chmod 0600 $ALTROOT/etc/svc/repository.db
  chown root:sys $ALTROOT/etc/svc/repository.db
  /usr/sbin/devfsadm -r /mnt
  [[ -L $ALTROOT/dev/msglog ]] || \
    ln -s ../devices/pseudo/sysmsg@0:msglog $ALTROOT/dev/msglog
  MakeSwapDump
  zfs destroy rpool/ROOT/omnios@kayak
}

FetchConfig(){
  ETHER=`Ether`
  BOOTSRVA=`/sbin/dhcpinfo BootSrvA`
  CONFIG=`getvar install_config`
  CONFIG=`echo $CONFIG | sed -e "s%//\:%//$BOOTSRVA\:%g;"`
  CONFIG=`echo $CONFIG | sed -e "s%///%//$BOOTSRVA/%g;"`
  L=${#ETHER}
  while [[ "$L" -gt "0" ]]; do
    URL="$CONFIG/${ETHER:0:$L}"
    log "... trying $URL"
    /bin/curl -s -o $ICFILE $URL
    if [[ -f $ICFILE ]]; then
      if [[ -n $(grep BuildRpool $ICFILE) ]]; then
        log "fetched config."
        return 0
      fi
      rm -f $ICFILE
    fi
    L=$(($L - 1))
  done
  return 1
}

MakeBootable(){
  log "Making boot environment bootable"
  mkdir -p /rpool/boot/grub/bootsign || bomb "mkdir rpool/boot/grub failed"
  touch /rpool/boot/grub/bootsign/pool_rpool || bomb "making bootsign failed"
  chown -R root:root /rpool/boot || bomb "rpool/boot chown failed"
  chmod 444 /rpool/boot/grub/bootsign/pool_rpool || bomb "chmod bootsign failed"
  for f in capability menu.lst splash.xpm.gz ; do
    cp -p $ALTROOT/boot/grub/$f /rpool/boot/grub/$f || \
      bomb "setup rpool/boot/grub/$f failed"
  done
  zpool set bootfs=rpool/ROOT/omnios rpool || bomb "setting bootfs failed"
  beadm activate omnios || bomb "activating be failed"
  $ALTROOT/boot/solaris/bin/update_grub -R $ALTROOT
  bootadm update-archive -R $ALTROOT
  RELEASE=`head -1 $ALTROOT/etc/release | sed -e 's/ *//;'`
  sed -i -e '/BOOTADM/,/BOOTADM/d' /rpool/boot/grub/menu.lst
  sed -i -e "s/^title.*/title $RELEASE/;" /rpool/boot/grub/menu.lst
  SendInstallLog
  CopyInstallLog
  beadm umount omnios
  return 0
}

SetHostname()
{
  log "Setting hostname: ${1}"
  /bin/hostname "$1"
  echo "$1" > $ALTROOT/etc/nodename
  head -n 26 $ALTROOT/etc/hosts > /tmp/hosts
  echo "::1\t\t$1" >> /tmp/hosts
  echo "127.0.0.1\t$1" >> /tmp/hosts
  cat /tmp/hosts > $ALTROOT/etc/hosts
}

AutoHostname() {
  suffix=$1
  macadr=`/sbin/ifconfig -a | \
          /usr/bin/awk '/UP/{if($2 !~ /LOOPBACK/){iface=$1;}} /ether/{if(iface){print $2; exit;}}' | \
          /bin/tr '[:upper:]' '[:lower:]' | \
          /bin/sed -e 's/^/ 0/g;s/:/-0/g; s/0\([0-9a-f][0-9a-f]\)/\1/g; s/ //g;'`
  [ -z $suffix ] && suffix=omnios
  [ "$suffix" == "-" ] && suffix= || suffix=-$suffix
  SetHostname $macadr$suffix
}

SetTimezone()
{
  log "Setting timezone: ${1}"
  sed -i -e "s:^TZ=.*:TZ=${1}:" $ALTROOT/etc/default/init
}

ApplyChanges(){
  SetRootPW
  [[ -L $ALTROOT/etc/svc/profile/generic.xml ]] || \
    ln -s generic_limited_net.xml $ALTROOT/etc/svc/profile/generic.xml
  [[ -L $ALTROOT/etc/svc/profile/name_service.xml ]] || \
    ln -s ns_dns.xml $ALTROOT/etc/svc/profile/name_service.xml
  return 0
}

Postboot() {
  [[ -f $ALTROOT/.initialboot ]] || touch $ALTROOT/.initialboot
  echo "$*" >> $ALTROOT/.initialboot
}

Reboot() {
  # This is an awful hack... we already setup bootadm
  # and we've likely deleted enough of the userspace that this
  # can't run successfully... The easiest way to skip it is to
  # remove the binary
  rm -f /sbin/bootadm
  svccfg -s "system/boot-config:default" setprop config/fastreboot_default=false
  svcadm refresh svc:/system/boot-config:default
  reboot
}

RunInstall(){
  FetchConfig || bomb "Could not fecth kayak config for target"
  . $ICFILE
  Postboot 'exit $SMF_EXIT_OK'
  ApplyChanges || bomb "Could not apply all configuration changes"
  MakeBootable || bomb "Could not make new BE bootable"
  log "Install complete"
  return 0
}
