#!/bin/sh

CONFIG_FILE="/opt/root/KeenSnap/config.conf"
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

if [ "$1" = "start" ] && [ "$schedule" = "$SCHEDULE_NAME" ]; then
  $PATH_SNAPD start "$schedule" &
fi
exit 0
