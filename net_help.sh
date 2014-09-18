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

Ether(){
  /sbin/ifconfig -a | \
    /usr/bin/awk '/UP/{if($2 !~ /LOOPBACK/){iface=$1;}} /ether/{if(iface){print $2; exit;}}' | \
    /bin/tr '[:lower:]' '[:upper:]' | \
    /bin/sed -e 's/^/ 0/g;s/:/ 0/g; s/0\([0-9A-F][0-9A-F]\)/\1/g; s/ //g;'
}

UseDNS() {
  server=$1; shift
  domain=$1
  EnableDNS $domain $*
  SetDNS $server
}

EnableDNS() {
  domain=$1
  if [ ! -z $domain ]; then
    cat <<EOF > $ALTROOT/etc/resolv.conf
domain $domain
search $*
EOF
  fi
  sed -I -e 's/^hosts:.*/hosts: files dns/;' $ALTROOT/etc/nsswitch.conf
  sed -I -e 's/^ipnodes:.*/ipnodes: files dns/;' $ALTROOT/etc/nsswitch.conf
}

SetDNS() {
# NOTE: If the nsswitch.conf file specifies DNS in a manner other than:
# "files dns", setting EnableDNS will have to become more sophisticated.
  /usr/bin/grep -c 'files dns' $ALTROOT/etc/nsswitch.conf 2> /dev/null > /dev/null || EnableDNS

  for srv in $*; do
    echo nameserver $srv >> $ALTROOT/etc/resolv.conf
  done
}
