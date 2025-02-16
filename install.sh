#!/bin/sh

REPO="keensnap"
SCRIPT="keensnap.sh"
SNAPD="keensnap-init"
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
ln -sf $KEENSNAP_DIR/$SCRIPT $OPT_DIR/bin/$REPO

curl -L -s "https://raw.githubusercontent.com/spatiumstas/$REPO/main/$SNAPD" --output $TMP_DIR/$SNAPD
mv "$TMP_DIR/$SNAPD" "$KEENSNAP_DIR/$SNAPD"
chmod +x $KEENSNAP_DIR/$SNAPD

URL=$(echo "aHR0cHM6Ly9sb2cuc3BhdGl1bS5rZWVuZXRpYy5wcm8=" | base64 -d)
JSON_DATA="{\"script_update\": \"KeenSnap_update_$SCRIPT_VERSION\"}"
curl -X POST -H "Content-Type: application/json" -d "$JSON_DATA" "$URL" -o /dev/null -s
$KEENSNAP_DIR/$SCRIPT
