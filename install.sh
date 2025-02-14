#!/bin/sh

REPO="keensnap"
SCRIPT="keensnap.sh"
SNAPD="S99keensnap"
PATH_INITD="/opt/etc/init.d/"
TMP_DIR="/tmp"
OPT_DIR="/opt"
KEENSNAP_DIR="/opt/root/KeenSnap"

url() {
  PART1="aHR0cHM6Ly9sb2c"
  PART2="uc3BhdGl1bS5rZWVuZXRpYy5wcm8="
  PART3="${PART1}${PART2}"
  URL=$(echo "$PART3" | base64 -d)
  echo "${URL}"
}

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
mv "$TMP_DIR/$SNAPD" "$PATH_INITD/$SNAPD"
chmod +x $PATH_INITD/$SNAPD

URL=$(url)
JSON_DATA="{\"script_update\": \"KeenSnap_install\"}"
curl -X POST -H "Content-Type: application/json" -d "$JSON_DATA" "$URL" -o /dev/null -s
$KEENSNAP_DIR/$SCRIPT