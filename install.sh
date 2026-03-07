#!/bin/sh

REPO="keensnap"
SCRIPT="keensnap.sh"
SNAPD="keensnap-init"
CONFIG="config.template"
TMP_DIR="/tmp"
OPT_DIR="/opt"
KEENSNAP_DIR="/opt/root/KeenSnap"
BRANCH="main-english"

print_message() {
  local message="$1"
  local color="${2:-$NC}"
  local border=$(printf '%0.s-' $(seq 1 $((${#message} + 2))))
  printf "${color}\n+${border}+\n| ${message} |\n+${border}+\n${NC}\n"
}

packages_checker() {
  local missing=""
  for pkg in "$@"; do
    if ! opkg list-installed | grep -q "^$pkg"; then
      missing="$missing $pkg"
    fi
  done
  if [ -n "$missing" ]; then
    print_message "Install:$missing"
    opkg update && opkg install $missing
    echo ""
  fi
}

packages_checker curl tar
curl -L -s "https://raw.githubusercontent.com/spatiumstas/$REPO/$BRANCH/$SCRIPT" --output $TMP_DIR/$SCRIPT
mkdir -p "$KEENSNAP_DIR"
mv "$TMP_DIR/$SCRIPT" "$KEENSNAP_DIR/$SCRIPT"
cd $OPT_DIR/bin && ln -sf $KEENSNAP_DIR/$SCRIPT $OPT_DIR/bin/$REPO
curl -L -s "https://raw.githubusercontent.com/spatiumstas/$REPO/$BRANCH/$SNAPD" --output $TMP_DIR/$SNAPD
mv "$TMP_DIR/$SNAPD" "$KEENSNAP_DIR/$SNAPD"
chmod -R +x "$KEENSNAP_DIR"
exec $KEENSNAP_DIR/$SCRIPT
