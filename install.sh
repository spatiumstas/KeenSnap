#!/bin/sh

printf "\033c"
set -e

echo "Устанавливаю репозиторий"
mkdir -p /opt/etc/opkg
echo "src/gz KeenSnap https://spatiumstas.github.io/KeenSnap/all" > /opt/etc/opkg/keensnap.conf

echo "Начинаю установку"
echo ""
opkg update && opkg install keensnap
