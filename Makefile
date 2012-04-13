VERSION=r151002
BUILDSEND=rpool/kayak_image


BUILDSEND_MP=$(shell zfs get -o value -H mountpoint $(BUILDSEND))

all:	$(BUILDSEND_MP)/miniroot.gz $(BUILDSEND_MP)/kayak_$(VERSION).zfs.bz2
	@ls -l $^

TFTP_FILES=$(DESTDIR)/tftpboot/boot/platform/i86pc/kernel/amd64/unix \
	$(DESTDIR)/tftpboot/omnios/kayak/miniroot.gz \
	$(DESTDIR)/tftpboot/menu.lst \
	$(DESTDIR)/tftpboot/pxegrub

WEB_FILES=$(DESTDIR)/var/kayak/kayak/$(VERSION).zfs.bz2

anon.dtrace.conf:
	dtrace -A -q -n'int seen[string]; fsinfo:::/substr(args[0]->fi_pathname,0,1)=="/" && seen[args[0]->fi_pathname]==0/{printf("%d %s %s\n",timestamp/1000000, args[0]->fi_pathname, args[0]->fi_mount);seen[args[0]->fi_pathname]=1;}' -o $@.tmp
	cat /kernel/drv/dtrace.conf $@.tmp > $@
	rm $@.tmp

MINIROOT_DEPS=build_image.sh anon.dtrace.conf anon.system \
	install_image.sh disk_help.sh install_help.sh net_help.sh

$(BUILDSEND_MP)/kayak_$(VERSION).zfs.bz2:	build_zfs_send.sh
	@test -d "$(BUILDSEND_MP)" || (echo "$(BUILDSEND) missing" && false)
	./build_zfs_send.sh -d $(BUILDSEND) $(VERSION)

$(DESTDIR)/tftpboot/pxegrub:	/boot/grub/pxegrub
	cp -p $< $@

$(DESTDIR)/tftpboot/menu.lst:	sample/menu.lst.000000000000
	cp -p $< $@

$(DESTDIR)/tftpboot/boot/platform/i86pc/kernel/amd64/unix:	/platform/i86pc/kernel/amd64/unix
	cp -p $< $@

$(DESTDIR)/tftpboot/omnios/kayak/miniroot.gz:	$(BUILDSEND_MP)/miniroot.gz
	cp -p $< $@

$(BUILDSEND_MP)/miniroot.gz:	$(MINIROOT_DEPS)
	./build_image.sh begin

install-dirs:
	mkdir -p $(DESTDIR)/tftpboot/boot/platform/i86pc/kernel/amd64
	mkdir -p $(DESTDIR)/tftpboot/omnios/kayak
	mkdir -p $(DESTDIR)/var/kayak/kayak

install:	install-dirs $(TFTP_FILES) $(WEB_FILES)
