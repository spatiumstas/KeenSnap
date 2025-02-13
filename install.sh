#!/bin/sh

REPO="KeenSnap"
SCRIPT="KeenSnap.sh"
TMP_DIR="/tmp"
OPT_DIR="/opt"
KEENSNAP_DIR="/opt/root/KeenSnap"

if ! opkg list-installed | grep -q "^curl"; then
  opkg update
  opkg install curl
fi

curl -L -s "https://raw.githubusercontent.com/spatiumstas/$REPO/main/$SCRIPT" --output $TMP_DIR/$SCRIPT
mkdir -p "$KEENSNAP_DIR"
mv "$TMP_DIR/$SCRIPT" "$KEENSNAP_DIR/$SCRIPT"
chmod +x $KEENSNAP_DIR/$SCRIPT
cd $OPT_DIR/bin
ln -sf $KEENSNAP_DIR/$SCRIPT $OPT_DIR/bin/keensnap
$KEENSNAP_DIR/$SCRIPT
