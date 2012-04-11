#!/usr/bin/bash

Ether(){
  /sbin/ifconfig -a | \
    /usr/bin/awk '/UP/{if($2 !~ /LOOPBACK/){iface=$1;}} /ether/{if(iface){print $2; exit;}}' | \
    /bin/tr -s '[:lower:]' '[:upper:]' | \
    /bin/sed -e 's/^/ 0/g;s/:/ 0/g; s/0\([0-9A-F][0-9A-F]\)/\1/g; s/ //g;'
}

UseDNS() {
  server=$1; shift
  domain=$1
  cat <<EOF > $ALTROOT/etc/resolv.conf
nameserver $server
domain $domain
search $*
EOF
  sed -I -e 's/^hosts:.*/hosts: files dns/;' $ALTROOT/etc/nsswitch.conf
}
