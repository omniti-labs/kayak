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

VERSION?=$(shell awk '$$1 == "OmniOS" { print $$3 }' /etc/release)
BUILDSEND=rpool/kayak_image


BUILDSEND_MP=$(shell zfs get -o value -H mountpoint $(BUILDSEND))

all:

INSTALLS=anon.dtrace.conf anon.system build_image.sh build_zfs_send.sh \
	data/access.log data/boot data/etc data/filelist.ramdisk data/kernel \
	data/known_extras data/mdb data/platform disk_help.sh install_help.sh \
	install_image.sh takeover-console.c Makefile net_help.sh README.md \
	build_iso.sh digest find-and-install.sh kayak-menu.sh usbgen.sh \
	loader.conf.local rpool-install.sh \
	sample/000000000000.sample sample/menu.lst.000000000000

TFTP_FILES=$(DESTDIR)/tftpboot/boot/platform/i86pc/kernel/amd64/unix \
	$(DESTDIR)/tftpboot/kayak/miniroot.gz \
	$(DESTDIR)/tftpboot/kayak/miniroot.gz.hash \
	$(DESTDIR)/tftpboot/boot/grub/menu.lst \
	$(DESTDIR)/tftpboot/pxeboot $(DESTDIR)/tftpboot/boot/loader.conf.local \
	$(DESTDIR)/tftpboot/boot/forth $(DESTDIR)/tftpboot/boot/defaults \
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

$(DESTDIR)/tftpboot/pxeboot:	/boot/pxeboot
	cp -p $< $@

$(DESTDIR)/tftpboot/boot/loader.conf.local:	loader.conf.local
	cp -p $< $@

$(DESTDIR)/tftpboot/boot/forth:	/boot/forth
	cp -rp $< $@

$(DESTDIR)/tftpboot/boot/defaults:	/boot/defaults
	cp -rp $< $@

$(DESTDIR)/tftpboot/boot/grub/menu.lst:	sample/menu.lst.000000000000
	sed -e 's/@VERSION@/$(VERSION)/' $< > $@

$(DESTDIR)/tftpboot/boot/platform/i86pc/kernel/amd64/unix:	/platform/i86pc/kernel/amd64/unix
	cp -p $< $@

$(DESTDIR)/tftpboot/kayak/miniroot.gz:	$(BUILDSEND_MP)/miniroot.gz
	cp -p $< $@

$(DESTDIR)/tftpboot/kayak/miniroot.gz.hash:	$(BUILDSEND_MP)/miniroot.gz
	digest -a sha1 $< > $@

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
	mkdir -p $(DESTDIR)/var/svc/manifest/network
	mkdir -p $(DESTDIR)/var/svc/method

install-package:	tftp-dirs server-dirs
	for file in $(INSTALLS) ; do \
		cp $$file $(DESTDIR)/usr/share/kayak/$$file ; \
	done
	cp http/svc-kayak $(DESTDIR)/var/svc/method/svc-kayak
	chmod a+x $(DESTDIR)/var/svc/method/svc-kayak
	cp http/css/land.css $(DESTDIR)/var/kayak/css/land.css
	for file in $(IMG_FILES) ; do \
		cp http/img/$$file $(DESTDIR)/var/kayak/img/$$file ; \
	done
	cp http/kayak.xml $(DESTDIR)/var/svc/manifest/network/kayak.xml

install-tftp:	tftp-dirs $(TFTP_FILES)

install-web:	server-dirs $(WEB_FILES)

takeover-console:	takeover-console.c
	gcc -o takeover-console takeover-console.c

install-iso:	takeover-console install-tftp install-web
	BUILDSEND_MP=$(BUILDSEND_MP) VERSION=$(VERSION) ./build_iso.sh

install-usb:	install-iso
	./usbgen.sh $(BUILDSEND_MP)/$(VERSION).iso $(BUILDSEND_MP)/$(VERSION).usb-dd /tmp
