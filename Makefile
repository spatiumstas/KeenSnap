SHELL := /bin/bash
VERSION := $(shell cat VERSION)
PACKAGE := keensnap
ROOT_DIR := /opt
DEPENDENCIES := curl, tar, ca-certificates, wget-ssl

.PHONY: clean _pkg-clean _pkg-control _pkg-scripts _pkg-ipk keensnap-ipk

clean:
	rm -rf out/pkg

_pkg-clean:
	rm -rf out/$(BUILD_DIR)
	mkdir -p out/$(BUILD_DIR)/control
	mkdir -p out/$(BUILD_DIR)/data

_pkg-control:
	echo "Package: $(PACKAGE)" > out/$(BUILD_DIR)/control/control
	echo "Version: $(VERSION)" >> out/$(BUILD_DIR)/control/control
	echo "Depends: $(DEPENDENCIES)" >> out/$(BUILD_DIR)/control/control
	echo "Section: utils" >> out/$(BUILD_DIR)/control/control
	echo "Architecture: all" >> out/$(BUILD_DIR)/control/control
	echo "License: MIT" >> out/$(BUILD_DIR)/control/control
	echo "URL: https://github.com/spatiumstas/keensnap" >> out/$(BUILD_DIR)/control/control
	echo "Description: Keenetic backup utility with Telegram and Google Drive support" >> out/$(BUILD_DIR)/control/control

_pkg-scripts:
	cp common/ipk/postinst out/$(BUILD_DIR)/control/postinst
	cp common/ipk/conffiles out/$(BUILD_DIR)/control/conffiles
	cp common/ipk/postrm out/$(BUILD_DIR)/control/postrm
	find out/$(BUILD_DIR)/control -type f -print0 | xargs -0 dos2unix
	chmod +x out/$(BUILD_DIR)/control/postinst
	chmod +x out/$(BUILD_DIR)/control/postrm
	chmod +x out/$(BUILD_DIR)/control/conffiles

_pkg-ipk:
	make _pkg-clean
	make _pkg-control
	make _pkg-scripts
	cd out/$(BUILD_DIR)/control; tar czvf ../control.tar.gz .; cd ../../..

	mkdir -p out/$(BUILD_DIR)/data$(ROOT_DIR)/root/KeenSnap
	sed 's/^SCRIPT_VERSION=""/SCRIPT_VERSION="$(VERSION)"/' common/keensnap-init > out/$(BUILD_DIR)/data$(ROOT_DIR)/root/KeenSnap/keensnap-init
	sed 's/^SCRIPT_VERSION=""/SCRIPT_VERSION="$(VERSION)"/' common/keensnap.sh > out/$(BUILD_DIR)/data$(ROOT_DIR)/root/KeenSnap/keensnap.sh
	cp common/config.conf out/$(BUILD_DIR)/data$(ROOT_DIR)/root/KeenSnap/config.conf
	cp common/99-keensnap.sh out/$(BUILD_DIR)/data$(ROOT_DIR)/root/KeenSnap/99-keensnap.sh
	find out/$(BUILD_DIR)/data$(ROOT_DIR)/root/KeenSnap -type f -print0 | xargs -0 dos2unix
	chmod +x out/$(BUILD_DIR)/data$(ROOT_DIR)/root/KeenSnap/keensnap.sh
	chmod +x out/$(BUILD_DIR)/data$(ROOT_DIR)/root/KeenSnap/keensnap-init
	chmod +x out/$(BUILD_DIR)/data$(ROOT_DIR)/root/KeenSnap/99-keensnap.sh
	cd out/$(BUILD_DIR)/data; tar czvf ../data.tar.gz .; cd ../../..

	echo 2.0 > out/$(BUILD_DIR)/debian-binary
	cd out/$(BUILD_DIR); \
	tar czvf ../$(PACKAGE)_$(VERSION).ipk control.tar.gz data.tar.gz debian-binary; \
	cd ../..

keensnap-ipk:
	@make \
		BUILD_DIR=pkg \
		_pkg-ipk
