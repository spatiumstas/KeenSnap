#!/bin/sh

REPO="keensnap"
SCRIPT="keensnap.sh"
SNAPD="keensnap-init"
CONFIG="config.template"
TMP_DIR="/tmp"
OPT_DIR="/opt"
KEENSNAP_DIR="/opt/root/KeenSnap"

if ! opkg list-installed | grep -q "^curl"; then
  opkg update && opkg install curl
fi

curl -L -s "https://raw.githubusercontent.com/spatiumstas/$REPO/main/$SCRIPT" --output $TMP_DIR/$SCRIPT
mkdir -p "$KEENSNAP_DIR"
mv "$TMP_DIR/$SCRIPT" "$KEENSNAP_DIR/$SCRIPT"
cd $OPT_DIR/bin && ln -sf $KEENSNAP_DIR/$SCRIPT $OPT_DIR/bin/$REPO
curl -L -s "https://raw.githubusercontent.com/spatiumstas/$REPO/main/$SNAPD" --output $TMP_DIR/$SNAPD
mv "$TMP_DIR/$SNAPD" "$KEENSNAP_DIR/$SNAPD"
chmod -R +x "$KEENSNAP_DIR"
$KEENSNAP_DIR/$SCRIPT
