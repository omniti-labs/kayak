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
# Copyright 2017 OmniTI Computer Consulting, Inc.  All rights reserved.
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
  RPOOL=${1:-rpool}
  if [[ -z $2 ]]; then
      BOOTSRVA=`/sbin/dhcpinfo BootSrvA`
      MEDIA=`getvar install_media`
      MEDIA=`echo $MEDIA | sed -e "s%//\:%//$BOOTSRVA\:%g;"`
      MEDIA=`echo $MEDIA | sed -e "s%///%//$BOOTSRVA/%g;"`
      DECOMP="bzip2 -dc"
      GRAB="curl -s"
  else
      # ASSUME $2 is a file path.  TODO: Parse the URL...
      MEDIA=$2
      # TODO: make switch statement based on $MEDIA's extension.
      # e.g. "bz2" ==> "bzip -dc", "7z" ==> 
      DECOMP="bzip2 -dc"
      GRAB=cat
  fi
  zfs set compression=on $RPOOL
  zfs create $RPOOL/ROOT
  zfs set canmount=off $RPOOL/ROOT
  zfs set mountpoint=legacy $RPOOL/ROOT
  log "Receiving image: $MEDIA"
  $GRAB $MEDIA | pv -B 128m -w 78 | $DECOMP | zfs receive -u $RPOOL/ROOT/omnios
  zfs set canmount=noauto $RPOOL/ROOT/omnios
  zfs set mountpoint=legacy $RPOOL/ROOT/omnios
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
  zfs destroy $RPOOL/ROOT/omnios@kayak
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
  RPOOL=${1:-rpool}
  log "Making boot environment bootable"
  zpool set bootfs=$RPOOL/ROOT/omnios rpool
  # Must do beadm activate first on the off chance we're bootstrapping from
  # GRUB.
  beadm activate omnios || return 1

  if [[ ! -z $1 ]]; then
      # Generate kayak-disk-list from zpool status.
      # NOTE: If this is something on non-s0 slices, the installboot below
      # will fail most likely, which is possibly a desired result.
      zpool list -v $RPOOL | egrep -v "NAME|rpool|mirror" | \
	  awk '{print $1}' | sed -E 's/s0$//g' > /tmp/kayak-disk-list
  fi

  # NOTE:  This installboot loop assumes we're doing GPT whole-disk rpools.
  for i in `cat /tmp/kayak-disk-list`
  do
      installboot -mfF /boot/pmbr /boot/gptzfsboot /dev/rdsk/${i}s0 || return 1
  done

  bootadm update-archive -R $ALTROOT || return 1
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

SetLang()
{
  log "Setting language: ${1}"
  sed -i -e "s:^LANG=.*:LANG=${1}:" $ALTROOT/etc/default/init
}

SetKeyboardLayout()
{
      # Put the new keyboard layout ($1) in
      # "setprop keyboard-layout <foo>" in the newly-installed root's
      # /boot/solaris/bootenv.rc (aka. eeprom(1M) storage for amd64/i386).
      layout=$1
      sed "s/keyboard-layout Unknown/keyboard-layout $layout/g" \
	  < $ALTROOT/boot/solaris/bootenv.rc > /tmp/bootenv.rc
      mv /tmp/bootenv.rc $ALTROOT/boot/solaris/bootenv.rc
      # Also modify the SMF manifest, assuming US-English was set by default.
      sed "s/US-English/$layout/g" \
	 < $ALTROOT/lib/svc/manifest/system/keymap.xml > /tmp/keymap.xml
      cp -f /tmp/keymap.xml $ALTROOT/lib/svc/manifest/system/keymap.xml
}

ApplyChanges(){
  SetRootPW
  [[ -L $ALTROOT/etc/svc/profile/generic.xml ]] || \
    ln -s generic_limited_net.xml $ALTROOT/etc/svc/profile/generic.xml
  [[ -L $ALTROOT/etc/svc/profile/name_service.xml ]] || \
    ln -s ns_dns.xml $ALTROOT/etc/svc/profile/name_service.xml

  # Extras from interactive ISO/USB install...
  # arg1 == hostname
  if [[ ! -z $1 ]]; then
      SetHostname $1
  fi

  # arg2 == timezone
  if [[ ! -z $2 ]]; then
      SetTimezone $2
  fi

  # arg3 == Language
  if [[ ! -z $3 ]]; then
      SetLang $3
  fi

  # arg4 == Keyboard layout
  if [[ ! -z $4 ]]; then
      SetKeyboardLayout $4
  fi

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
  FetchConfig || bomb "Could not fetch kayak config for target"
  # Set RPOOL if it wasn't done so already. We need it set.
  RPOOL=${RPOOL:-rpool}
  . $ICFILE
  Postboot 'exit $SMF_EXIT_OK'
  ApplyChanges || bomb "Could not apply all configuration changes"
  MakeBootable || bomb "Could not make new BE bootable"
  log "Install complete"
  return 0
}
