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

VERSION?=$(shell awk '$$1 == "OmniOS" { print $$3 }' /etc/release)
BUILDSEND=rpool/kayak_image


BUILDSEND_MP=$(shell zfs get -o value -H mountpoint $(BUILDSEND))

all:

INSTALLS=anon.dtrace.conf anon.system build_image.sh build_zfs_send.sh \
	data/access.log data/boot data/etc data/filelist.ramdisk data/kernel \
	data/known_extras data/mdb data/platform disk_help.sh install_help.sh \
	install_image.sh Makefile net_help.sh README.md \
	sample/000000000000.sample sample/menu.lst.000000000000

TFTP_FILES=$(DESTDIR)/tftpboot/boot/platform/i86pc/kernel/amd64/unix \
	$(DESTDIR)/tftpboot/kayak/miniroot.gz \
	$(DESTDIR)/tftpboot/boot/grub/menu.lst \
	$(DESTDIR)/tftpboot/pxegrub

WEB_FILES=$(DESTDIR)/var/kayak/kayak/$(VERSION).zfs.bz2
IMG_FILES=corner.png tail_bg_v1.png OmniOS_logo_medium.png tail_bg_v2.png

anon.dtrace.conf:
	dtrace -A -q -n'int seen[string]; fsinfo:::/args[0]->fi_mount=="/" && seen[args[0]->fi_pathname]==0/{printf("%d %s\n",timestamp/1000000, args[0]->fi_pathname);seen[args[0]->fi_pathname]=1;}' -o $@.tmp
	cat /kernel/drv/dtrace.conf $@.tmp > $@
	rm $@.tmp

MINIROOT_DEPS=build_image.sh anon.dtrace.conf anon.system \
	install_image.sh disk_help.sh install_help.sh net_help.sh

$(BUILDSEND_MP)/kayak_$(VERSION).zfs.bz2:	build_zfs_send.sh
	@test -d "$(BUILDSEND_MP)" || (echo "$(BUILDSEND) missing" && false)
	./build_zfs_send.sh -d $(BUILDSEND) $(VERSION)

$(DESTDIR)/tftpboot/pxegrub:	/boot/grub/pxegrub
	cp -p $< $@

$(DESTDIR)/tftpboot/boot/grub/menu.lst:	sample/menu.lst.000000000000
	sed -e 's/@VERSION@/$(VERSION)/' $< > $@

$(DESTDIR)/tftpboot/boot/platform/i86pc/kernel/amd64/unix:	/platform/i86pc/kernel/amd64/unix
	cp -p $< $@

$(DESTDIR)/tftpboot/kayak/miniroot.gz:	$(BUILDSEND_MP)/miniroot.gz
	cp -p $< $@

build_image.sh:
	VERSION=$(VERSION) ./build_image.sh

build_zfs_send.sh:
	VERSION=$(VERSION) ./build_zfs_image.sh

$(BUILDSEND_MP)/miniroot.gz:	$(MINIROOT_DEPS)
	if test -n "`zfs list -H -t snapshot $(BUILDSEND)/root@fixup 2>/dev/null`"; then \
	  VERSION=$(VERSION) DEBUG=$(DEBUG) ./build_image.sh $(BUILDSEND) fixup ; \
	else \
	  VERSION=$(VERSION) DEBUG=$(DEBUG) ./build_image.sh $(BUILDSEND) begin ; \
	fi

$(DESTDIR)/var/kayak/kayak/$(VERSION).zfs.bz2:	$(BUILDSEND_MP)/kayak_$(VERSION).zfs.bz2
	cp -p $< $@

tftp-dirs:
	mkdir -p $(DESTDIR)/tftpboot/boot/grub
	mkdir -p $(DESTDIR)/tftpboot/boot/platform/i86pc/kernel/amd64
	mkdir -p $(DESTDIR)/tftpboot/kayak

server-dirs:
	mkdir -p $(DESTDIR)/var/kayak/kayak
	mkdir -p $(DESTDIR)/var/kayak/css
	mkdir -p $(DESTDIR)/var/kayak/img
	mkdir -p $(DESTDIR)/usr/share/kayak/data
	mkdir -p $(DESTDIR)/usr/share/kayak/sample
	mkdir -p $(DESTDIR)/var/kayak/log
	mkdir -p $(DESTDIR)/lib/svc/manifest/network
	mkdir -p $(DESTDIR)/lib/svc/method

install-package:	tftp-dirs server-dirs
	for file in $(INSTALLS) ; do \
		cp $$file $(DESTDIR)/usr/share/kayak/$$file ; \
	done
	cp http/svc-kayak $(DESTDIR)/lib/svc/method/svc-kayak
	chmod a+x $(DESTDIR)/lib/svc/method/svc-kayak
	cp http/css/land.css $(DESTDIR)/var/kayak/css/land.css
	for file in $(IMG_FILES) ; do \
		cp http/img/$$file $(DESTDIR)/var/kayak/img/$$file ; \
	done
	cp http/kayak.xml $(DESTDIR)/lib/svc/manifest/network/kayak.xml

install-tftp:	tftp-dirs $(TFTP_FILES)

install-web:	server-dirs $(WEB_FILES)
