#!/bin/sh
trap cleanup HUP INT TERM EXIT
CONFIG_FILE="/opt/root/KeenSnap/config.conf"
RED='\033[1;31m'
GREEN='\033[1;32m'
CYAN='\033[0;36m'
NC='\033[0m'
USERNAME="spatiumstas"
REPO="keensnap"
SCRIPT="keensnap.sh"
BRANCH="main"
TMP_DIR="/tmp"
OPT_DIR="/opt"
STORAGE_DIR="/storage"
KEENSNAP_DIR="/opt/root/KeenSnap"
SNAPD="keensnap-init"
PATH_SCHEDULE="/opt/etc/ndm/schedule.d/99-keensnap.sh"
KEENSNAP_REPO_FILE="/opt/etc/opkg/keensnap.conf"
SCRIPT_VERSION=""
KEENSNAP_USERAGENT="KeenSnap/$SCRIPT_VERSION"
RCI_URL="http://127.0.0.1:79/rci"

print_menu() {
  printf "\033c"
  printf "${CYAN}"
  cat <<'EOF'
    __ __               _____                 
   / //_/__  ___  ____ / ___/____  ____ _____ 
  / ,< / _ \/ _ \/ __ \\__ \/ __ \/ __ `/ __ \
 / /| /  __/  __/ / / /__/ / / / / /_/ / /_/ /
/_/ |_\___/\___/_/ /_/____/_/ /_/\__,_/ .___/ 
                                     /_/      

EOF
  current_drive=$(get_config_value "SELECTED_DRIVE")
  current_upload_methods=$(get_config_value "UPLOAD_METHOD")
  current_backup_content=$(get_backup_content)
  printf "${CYAN}Модель:         ${NC}%s\n" "$(get_device) ($(get_hw_id)) | $(get_fw_version)"
  if [ -n "$current_drive" ]; then
    printf "${CYAN}Накопитель:     ${NC}%s\n" "$current_drive"
  fi
  if [ -n "$current_upload_methods" ]; then
    printf "${CYAN}Отправка:       ${NC}%s\n" "$current_upload_methods"
  fi
  if [ -n "$current_backup_content" ]; then
    printf "${CYAN}Состав:         ${NC}%s\n" "$current_backup_content"
  fi
  printf "${CYAN}Версия:         ${NC}%s\n\n" "$SCRIPT_VERSION by ${USERNAME}"
  echo "1. Запустить бэкап"
  echo "2. Параметры"
  echo "3. Показать конфиг"
  echo "4. Показать логи"
  printf "\n99. Обновить скрипт\n"  
  echo "00. Выход"
  echo ""
}

main_menu() {
  while true; do
    print_menu
    if ! read -r -p "Выберите действие: " choice; then
      echo ""
      exit 0
    fi
    echo ""
    choice=$(echo "$choice" | tr -d '\032' | tr -d '[A-Z]')

    if [ -z "$choice" ]; then
      continue
    fi
    case "$choice" in
    1) manual_backup ;;
    2) settings_menu ;;
    3) show_config ;;
    4) show_logs ;;
    99) script_update "interactive" ;;
    00) exit 0 ;;
    *)
      echo "Неверный выбор. Попробуйте снова."
      sleep 1
      ;;
    esac
  done
}

print_message() {
  message="$1"
  color="${2:-$NC}"
  border=$(printf '%0.s-' $(seq 1 $((${#message} + 2))))
  printf "${color}\n+${border}+\n| ${message} |\n+${border}+\n${NC}\n"
  sleep 2
}

exit_function() {
  echo ""
  read -n 1 -s -r -p "Для возврата нажмите любую клавишу..."
  pkill -P $$ 2>/dev/null
  exec "$KEENSNAP_DIR/$SCRIPT"
}

rci_curl() {
  local rci_token
  rci_token=$(get_config_value "RCI_TOKEN")
  if [ -n "$rci_token" ]; then
    curl -A "$KEENSNAP_USERAGENT" -H "X-Ndma-Tkn: $rci_token" "$@"
  else
    curl -A "$KEENSNAP_USERAGENT" "$@"
  fi
}

rci_request() {
  local endpoint="$1"
  rci_curl -s "$RCI_URL/$endpoint"
}

ndmc_cli() {
  unset LD_LIBRARY_PATH
  ndmc -c "$@"
}

get_device() {
  rci_request "show/version" | grep -o '"device": "[^"]*"' | cut -d'"' -f4 2>/dev/null
}

get_fw_version() {
  rci_request "show/version" | grep -o '"release": "[^"]*"' | cut -d'"' -f4 2>/dev/null
}

get_hw_id() {
  rci_request "show/version" | grep -o '"hw_id": "[^"]*"' | cut -d'"' -f4 2>/dev/null
}

get_backup_content() {
  local selected=""
  local entry
  local key
  local label

  for entry in \
    "BACKUP_STARTUP_CONFIG:Startup-Config" \
    "BACKUP_FIRMWARE:Firmware" \
    "BACKUP_ENTWARE:Entware" \
    "BACKUP_WG_PRIVATE_KEY:WireGuard-Private-Key"; do
    key=${entry%%:*}
    label=${entry#*:}
    [ "$(get_config_bool "$key" "false")" = "true" ] && selected="${selected}${selected:+, }$label"
  done

  [ -n "$selected" ] && echo "$selected"
}

select_schedule() {
  local message="$1"
  local schedules=""
  local index=1
  local schedule_output
  local parsed_schedules
  packages_checker "jq" || return 1

  schedule_output=$(rci_request "show/sc/schedule")

  if [ -z "$schedule_output" ]; then
    print_message "Расписания не найдены" "$RED"
    return 1
  fi

  parsed_schedules=$(printf '%s\n' "$schedule_output" | jq -r '
    to_entries[]
    | select(.key | startswith("schedule"))
    | [(.key // ""), (.value.description // "")]
    | @tsv
  ' 2>/dev/null)

  while IFS=$(printf '\t') read -r name desc; do
    [ -z "$name" ] && continue
    if [ -n "$desc" ]; then
      echo "$index. $name ($desc)"
    else
      echo "$index. $name"
    fi
    schedules="$schedules $index:$name"
    index=$((index + 1))
  done <<EOF
$parsed_schedules
EOF

  if [ -z "$schedules" ]; then
    print_message "Расписания не найдены" "$RED"
    return 1
  fi
  echo "00. Назад"
  echo ""
  read -p "$message " choice
  choice=$(echo "$choice" | tr -d ' \n\r')
  [ "$choice" = "00" ] && return 1

  SCHEDULE_SELECTED=$(echo "$schedules" | tr ' ' '\n' | grep "^$choice:" | cut -d ':' -f2)
  if [ -z "$SCHEDULE_SELECTED" ]; then
    print_message "Неверный выбор" "$RED"
    return 1
  fi
  return 0
}

get_config_raw() {
  local key="$1"
  grep "^$key=" "$CONFIG_FILE" 2>/dev/null | head -n 1 | cut -d '=' -f2-
}

get_config_value() {
  local key="$1"
  get_config_raw "$key" | sed 's/^"//;s/"$//'
}

get_config_bool() {
  local key="$1"
  local default="$2"
  local value
  value=$(get_config_raw "$key")
  case "$value" in
  true | false) echo "$value" ;;
  *) echo "$default" ;;
  esac
}

get_config_number() {
  local key="$1"
  local default="$2"
  local value
  value=$(get_config_raw "$key")
  if echo "$value" | grep -Eq '^[0-9]+$'; then
    echo "$value"
  else
    echo "$default"
  fi
}

append_config_line() {
  local line="$1"
  [ -f "$CONFIG_FILE" ] || : >"$CONFIG_FILE"

  if [ -s "$CONFIG_FILE" ]; then
    local last_char
    last_char=$(tail -c 1 "$CONFIG_FILE" 2>/dev/null)
    [ -n "$last_char" ] && printf '\n' >>"$CONFIG_FILE"
  fi

  printf '%s\n' "$line" >>"$CONFIG_FILE"
}

set_config_value() {
  local key="$1"
  local value="$2"
  if grep -q "^$key=" "$CONFIG_FILE" 2>/dev/null; then
    sed -i "s|^$key=.*|$key=\"$value\"|" "$CONFIG_FILE"
  else
    append_config_line "$key=\"$value\""
  fi
}

set_config_number() {
  local key="$1"
  local value="$2"
  if grep -q "^$key=" "$CONFIG_FILE" 2>/dev/null; then
    sed -i "s|^$key=.*|$key=$value|" "$CONFIG_FILE"
  else
    append_config_line "$key=$value"
  fi
}

format_size() {
  local used=$1
  local total=$2
  local used_mb=$((used / 1024 / 1024))
  local total_mb=$((total / 1024 / 1024))
  if [ "$total_mb" -ge 1024 ]; then
    total_gb=$((total / 1024 / 1024 / 1024))
    if [ "$used_mb" -lt 1024 ]; then
      printf "%d MB / %d GB" $used_mb $total_gb
    else
      used_gb=$((used / 1024 / 1024 / 1024))
      printf "%d / %d GB" $used_gb $total_gb
    fi
  else
    printf "%d / %d MB" $used_mb $total_mb
  fi
}

setup_config() {
  mkdir -p "$KEENSNAP_DIR"
  if [ ! -f "$CONFIG_FILE" ]; then
    print_message "Файл конфигурации не найден. Переустановите пакет $REPO" "$RED"
    return 1
  fi

  dos2unix "$CONFIG_FILE" >/dev/null 2>&1
}

toggle_boolean_option() {
  local key="$1"
  current_value=$(get_config_raw "$key")

  case "$current_value" in
    true | false) ;;
    *) current_value="false" ;;
  esac

  if [ "$current_value" = "true" ]; then
    if grep -q "^$key=" "$CONFIG_FILE" 2>/dev/null; then
      sed -i "s/^$key=.*/$key=false/" "$CONFIG_FILE"
    else
      append_config_line "$key=false"
    fi
  else
    if grep -q "^$key=" "$CONFIG_FILE" 2>/dev/null; then
      sed -i "s/^$key=.*/$key=true/" "$CONFIG_FILE"
    else
      append_config_line "$key=true"
    fi
  fi
}

show_config() {
  check_config
  printf "${GREEN}"
  cat "$CONFIG_FILE"
  printf "${NC}\n"
  exit_function
}

show_logs() {
  check_config
  if [ -f "/opt/var/log/keensnap.log" ]; then
    cat "/opt/var/log/keensnap.log"
  else
    echo "Лог-файл пока не создан"
  fi
  exit_function
}

setup_upload_method() {
  check_config
  while true; do
    printf "\033c"
    printf "Текущий способ: %s\n\n" "$(get_config_value "UPLOAD_METHOD")"
    echo "Введите номера через пробел (допустимо несколько):"
    echo "0. Без отправки"
    echo "1. Telegram"
    echo "2. Google Drive"
    echo "3. WebDAV"
    echo "00. Назад"
    echo ""
    read -p "Выбор: " upload_choice
    [ -z "$upload_choice" ] && return 0
    [ "$upload_choice" = "00" ] && return 0

    local selected_methods=""
    for choice in $upload_choice; do
      case "$choice" in
        0) selected_methods="$selected_methods" ;;
        1) selected_methods="$selected_methods Telegram" ;;
        2) selected_methods="$selected_methods GDrive" ;;
        3) selected_methods="$selected_methods WebDAV" ;;
      esac
    done

    selected_methods=$(echo "$selected_methods" | tr ' ' '\n' | sed '/^$/d' | awk '!seen[$0]++ { if (out) out=out","$0; else out=$0 } END { print out }')
    [ -z "$selected_methods" ] && selected_methods="$current_method"
    set_config_value "UPLOAD_METHOD" "$selected_methods"
    UPLOAD_METHOD="$selected_methods"
    dos2unix "$CONFIG_FILE"
  done
}

setup_telegram_settings() {
  check_config
  current_token=$(get_config_value "BOT_TOKEN")
  current_chat=$(get_config_value "CHAT_ID")
  current_proxy_interface=$(get_config_value "PROXY_INTERFACE")
  current_proxy_url=$(get_config_value "TG_PROXY")
  echo "00. Назад"

  read -p "BOT_TOKEN (Enter = оставить, '-' = очистить): " value
  [ "$value" = "00" ] && return 0
  if [ "$value" = "-" ]; then
    current_token=""
  elif [ -n "$value" ]; then
    current_token="$value"
  fi

  read -p "CHAT_ID (Enter = оставить, '-' = очистить): " value
  [ "$value" = "00" ] && return 0
  if [ "$value" = "-" ]; then
    current_chat=""
  elif [ -n "$value" ]; then
    current_chat="$value"
  fi

  read -p "PROXY_INTERFACE (например nwg0, Enter = оставить, '-' = очистить): " value
  [ "$value" = "00" ] && return 0
  if [ "$value" = "-" ]; then
    current_proxy_interface=""
  elif [ -n "$value" ]; then
    current_proxy_interface="$value"
  fi

  read -p "TG_PROXY URL (например socks5://127.0.0.1:1080, Enter = оставить, '-' = очистить): " value
  [ "$value" = "00" ] && return 0
  if [ "$value" = "-" ]; then
    current_proxy_url=""
  elif [ -n "$value" ]; then
    current_proxy_url="$value"
  fi

  set_config_value "BOT_TOKEN" "$current_token"
  set_config_value "CHAT_ID" "$current_chat"
  set_config_value "PROXY_INTERFACE" "$current_proxy_interface"
  set_config_value "TG_PROXY" "$current_proxy_url"
  dos2unix "$CONFIG_FILE"
  print_message "Параметры Telegram обновлены" "$GREEN"
}

setup_google_drive_settings() {
  check_config
  gd_id=$(get_config_value "GD_CLIENT_ID")
  gd_secret=$(get_config_value "GD_CLIENT_SECRET")
  gd_refresh=$(get_config_value "GD_REFRESH_TOKEN")
  gd_folder=$(get_config_value "GD_FOLDER_ID")
  echo "00. Назад"

  read -p "GD_CLIENT_ID (Enter = оставить, '-' = очистить): " value
  [ "$value" = "00" ] && return 0
  if [ "$value" = "-" ]; then
    gd_id=""
  elif [ -n "$value" ]; then
    gd_id="$value"
  fi

  read -p "GD_CLIENT_SECRET (Enter = оставить, '-' = очистить): " value
  [ "$value" = "00" ] && return 0
  if [ "$value" = "-" ]; then
    gd_secret=""
  elif [ -n "$value" ]; then
    gd_secret="$value"
  fi

  read -p "GD_REFRESH_TOKEN (Enter = оставить, '-' = очистить): " value
  [ "$value" = "00" ] && return 0
  if [ "$value" = "-" ]; then
    gd_refresh=""
  elif [ -n "$value" ]; then
    gd_refresh="$value"
  fi

  read -p "GD_FOLDER_ID (Enter = оставить, '-' = очистить): " value
  [ "$value" = "00" ] && return 0
  if [ "$value" = "-" ]; then
    gd_folder=""
  elif [ -n "$value" ]; then
    gd_folder="$value"
  fi

  set_config_value "GD_CLIENT_ID" "$gd_id"
  set_config_value "GD_CLIENT_SECRET" "$gd_secret"
  set_config_value "GD_REFRESH_TOKEN" "$gd_refresh"
  set_config_value "GD_FOLDER_ID" "$gd_folder"
  dos2unix "$CONFIG_FILE"
  print_message "Параметры Google Drive обновлены" "$GREEN"
}

setup_webdav_settings() {
  check_config
  wd_url=$(get_config_value "WD_URL")
  wd_username=$(get_config_value "WD_USERNAME")
  wd_password=$(get_config_value "WD_PASSWORD")
  wd_insecure=$(get_config_bool "WD_INSECURE" "false")
  echo "00. Назад"

  read -p "WD_URL (полный путь, Enter = оставить, '-' = очистить): " value
  [ "$value" = "00" ] && return 0
  if [ "$value" = "-" ]; then
    wd_url=""
  elif [ -n "$value" ]; then
    wd_url="$value"
  fi

  read -p "WD_USERNAME (Enter = оставить, '-' = очистить): " value
  [ "$value" = "00" ] && return 0
  if [ "$value" = "-" ]; then
    wd_username=""
  elif [ -n "$value" ]; then
    wd_username="$value"
  fi

  read -p "WD_PASSWORD (Enter = оставить, '-' = очистить): " value
  [ "$value" = "00" ] && return 0
  if [ "$value" = "-" ]; then
    wd_password=""
  elif [ -n "$value" ]; then
    wd_password="$value"
  fi

  read -p "WD_INSECURE (true/false, Enter = оставить): " value
  [ "$value" = "00" ] && return 0
  if [ -n "$value" ]; then
    case "$value" in
      true|false) wd_insecure="$value" ;;
      *) print_message "Допустимо true/false" "$RED" ;;
    esac
  fi

  set_config_value "WD_URL" "$wd_url"
  set_config_value "WD_USERNAME" "$wd_username"
  set_config_value "WD_PASSWORD" "$wd_password"
  if grep -q "^WD_INSECURE=" "$CONFIG_FILE" 2>/dev/null; then
    sed -i "s|^WD_INSECURE=.*|WD_INSECURE=$wd_insecure|" "$CONFIG_FILE"
  else
    append_config_line "WD_INSECURE=$wd_insecure"
  fi
  dos2unix "$CONFIG_FILE"
  print_message "Параметры WebDAV обновлены" "$GREEN"
}

setup_runtime_settings() {
  check_config
  while true; do
    printf "\033c"
    printf "Параметры:\n\n"
    retain_days=$(get_config_raw "RETAIN_ARCHIVES_DAYS")
    auto_update=$(get_config_raw "AUTO_UPDATE")
    delete_archive=$(get_config_raw "DELETE_LOCAL_ARCHIVE_AFTER_BACKUP")

    printf "1. AUTO_UPDATE=%s\n" "$auto_update"
    printf "2. RETAIN_ARCHIVES_DAYS=%s\n" "$retain_days"
    printf "3. DELETE_LOCAL_ARCHIVE_AFTER_BACKUP=%s\n" "$delete_archive"
    printf "4. ARCHIVE_PASSWORD=%s\n" "$(get_config_value "ARCHIVE_PASSWORD")"
    printf "5. ENTWARE_EXCLUDE=%s\n" "$(get_config_value "ENTWARE_EXCLUDE")"
    printf "6. RCI_TOKEN=%s\n" "$(get_config_value "RCI_TOKEN")"
    printf "00. Назад\n\n"
    read -p "Выберите параметр: " setting_choice

    case "$setting_choice" in
      00) return 0 ;;
      1) toggle_boolean_option "AUTO_UPDATE" ;;
      2)
        echo ""
        read -p "Введите число дней хранения локальных архивов (0 - отключить): " value
        if echo "$value" | grep -Eq '^[0-9]+$'; then
          set_config_number "RETAIN_ARCHIVES_DAYS" "$value"
        fi
        ;;
      3) toggle_boolean_option "DELETE_LOCAL_ARCHIVE_AFTER_BACKUP" ;;
      4)
        echo ""
        read -p "Введите пароль для архива (Enter = оставить, '-' = очистить): " value
        if [ "$value" = "-" ]; then
          set_config_value "ARCHIVE_PASSWORD" ""
        elif [ -n "$value" ]; then
          set_config_value "ARCHIVE_PASSWORD" "$value"
        fi
        ;;
      5)
        echo ""
        read -p "Введите список директорий для исключения бэкапа (через пробел, например '/bin /var/log', Enter = оставить, '-' = очистить): " value
        if [ "$value" = "-" ]; then
          set_config_value "ENTWARE_EXCLUDE" ""
        elif [ -n "$value" ]; then
          set_config_value "ENTWARE_EXCLUDE" "$value"
        fi
        ;;
      6)
        echo ""
        read -p "Введите RCI токен ( Enter = оставить, '-' = очистить): " value
        if [ "$value" = "-" ]; then
          set_config_value "RCI_TOKEN" ""
        elif [ -n "$value" ]; then
          set_config_value "RCI_TOKEN" "$value"
        fi
        ;;
      *) echo "Неверный выбор"; sleep 1 ;;
    esac

    dos2unix "$CONFIG_FILE"
  done
}

setup_backup_content() {
  check_config
  while true; do
    printf "\033c"
    printf "Состав бэкапа:\n\n"
    echo "1. BACKUP_STARTUP_CONFIG=$(get_config_bool "BACKUP_STARTUP_CONFIG" "false")"
    echo "2. BACKUP_FIRMWARE=$(get_config_bool "BACKUP_FIRMWARE" "false")"
    echo "3. BACKUP_ENTWARE=$(get_config_bool "BACKUP_ENTWARE" "false")"
    echo "4. BACKUP_WG_PRIVATE_KEY=$(get_config_bool "BACKUP_WG_PRIVATE_KEY" "false")"
    printf "00. Назад\n\n"
    read -p "Выберите параметр для переключения: " backup_choice
    echo ""

    case "$backup_choice" in
      1) toggle_boolean_option "BACKUP_STARTUP_CONFIG" ;;
      2) toggle_boolean_option "BACKUP_FIRMWARE" ;;
      3) toggle_boolean_option "BACKUP_ENTWARE" ;;
      4) toggle_boolean_option "BACKUP_WG_PRIVATE_KEY" ;;
      00) break ;;
      *) echo "Неверный выбор" ;;
    esac
    dos2unix "$CONFIG_FILE"
  done
}

setup_schedule_menu() {
  check_config
  while true; do
    printf "\033c"
    printf "Параметры расписания и накопителя:\n\n"
    printf "1. Расписание: %s\n" "$(get_config_value "SCHEDULE_NAME")"
    printf "2. Накопитель: %s\n" "$(get_config_value "SELECTED_DRIVE")"
    printf "00. Назад\n\n"
    read -p "Выберите параметр: " choice
    echo ""
    case "$choice" in
      00)
        return 0
        ;;
      1)
        if ! select_schedule "Выберите номер расписания:"; then
          :
        else
          if [ -n "$SCHEDULE_SELECTED" ]; then
            sed -i "s|^SCHEDULE_NAME=.*|SCHEDULE_NAME=\"$SCHEDULE_SELECTED\"|" "$CONFIG_FILE"
            dos2unix "$CONFIG_FILE"
          fi
        fi
        ;;
      2)
        if ! select_drive "Выберите накопитель для бэкапа:"; then
          :
        else
          sed -i "s|^SELECTED_DRIVE=.*|SELECTED_DRIVE=\"$selected_drive\"|" "$CONFIG_FILE"
          dos2unix "$CONFIG_FILE"
        fi
        ;;
      *) echo "Неверный выбор"; sleep 1 ;;
    esac
  done
}

settings_menu() {
  check_config
  while true; do
    printf "\033c"
    printf "Параметры KeenSnap:\n\n"
    echo "1. Расписание и накопитель"
    echo "2. Способ отправки"
    echo "3. Telegram"
    echo "4. Google Drive"
    echo "5. WebDAV"
    echo "6. Состав бэкапа"
    echo "7. Автоудаление, обновления, пароль, токен"
    echo "00. Назад"
    echo ""
    read -p "Выберите действие: " action
    echo ""
    case "$action" in
      1) setup_schedule_menu ;;
      2) setup_upload_method ;;
      3) setup_telegram_settings ;;
      4) setup_google_drive_settings ;;
      5) setup_webdav_settings ;;
      6) setup_backup_content ;;
      7) setup_runtime_settings ;;
      00) break ;;
      *) echo "Неверный выбор"; sleep 1 ;;
    esac
  done
}

check_config() {
  if [ ! -f "$CONFIG_FILE" ]; then
    print_message "Не выполнена начальная конфигурация" "$RED"
    exit_function
  fi
}

manual_backup() {
  "$KEENSNAP_DIR/$SNAPD" start manual
  exit_function
}

select_drive() {
  local message="$1"
  local media_output parsed_output
  local uuid display_name fstype total_bytes free_bytes used_bytes

  if ! packages_checker "jq"; then
    print_message "Не удалось установить jq" "$RED"
    return 1
  fi

  local uuids=""
  local index=1
  media_output=$(rci_request "ls")
  echo "0. Встроенное хранилище (может не хватить места)"

  parsed_output=$(printf '%s\n' "$media_output" | jq -r '
    .entry | to_entries[]
    | select(.value.storage? == "usb" and (.value.fstype? // "" | ascii_downcase) != "swap" and (.value.mounted? // "") == "yes")
    | [
        (.key | rtrimstr(":")),
        (.value.label // (.key | rtrimstr(":")) // "Unknown"),
        ((.value.fstype // "") | ascii_upcase),
        (.value.total // "0"),
        (.value.free // "0")
      ]
    | @tsv
  ' 2>/dev/null)

  while IFS=$(printf '\t') read -r uuid display_name fstype total_bytes free_bytes; do
    [ -z "$uuid" ] && continue
    echo "$total_bytes" | grep -qE '^[0-9]+$' || total_bytes=0
    echo "$free_bytes" | grep -qE '^[0-9]+$' || free_bytes=0
    used_bytes=$((total_bytes - free_bytes))
    [ "$used_bytes" -lt 0 ] && used_bytes=0

    echo "$index. $display_name ($fstype, $(format_size $used_bytes $total_bytes))"
    if [ -n "$uuids" ]; then
      uuids="$uuids
$uuid"
    else
      uuids="$uuid"
    fi
    index=$((index + 1))
  done <<EOF
$parsed_output
EOF
  printf "00. Назад\n\n"
  read -p "$message " choice
  choice=$(echo "$choice" | tr -d ' \n\r')
  if [ "$choice" = "00" ]; then
    return 1
  elif [ "$choice" = "0" ]; then
    selected_drive="/storage"
  else
      selected_drive=$(printf '%s\n' "$uuids" | sed -n "$((choice))p")
      if [ -z "$selected_drive" ]; then
        print_message "Неверный выбор" "$RED"
        return 1
      fi
      selected_drive="/tmp/mnt/$selected_drive"

    while true; do
      echo ""
      echo "Содержимое $selected_drive:"
      folders_list=$(find "$selected_drive" -maxdepth 1 -type d 2>/dev/null | grep -v "^$selected_drive$" | grep -v '/\\.' | grep -vE '/[А-Яа-яЁё]' | sort)
      set -- $folders_list
      folder_count=$#
      if [ $folder_count -eq 0 ]; then
        printf "${RED}Директория пустая ${NC}\n"
      else
        i=1
        for folder in "$@"; do
          fname="${folder##*/}"
          echo "$i. $fname"
          i=$((i + 1))
        done
      fi
      read -p "Выберите папку, 0 — выбрать текущую, 00 — уровень назад: " folder_choice
      if [ -z "$folder_choice" ] || [ "$folder_choice" = "0" ]; then
        break
      elif echo "$folder_choice" | grep -Eq '^[0-9]+$' && [ "$folder_choice" -ge 1 ] && [ "$folder_choice" -le "$folder_count" ]; then
        selected_drive=$(printf '%s\n' "$@" | sed -n "${folder_choice}p")
      elif [ "$folder_choice" = "00" ] && [ "$selected_drive" != "/tmp/mnt/$uuid" ]; then
        selected_drive=$(dirname "$selected_drive")
      else
        echo "Неверный выбор. Попробуйте снова."
      fi
    done
  fi
}

packages_checker() {
  local missing=""
  for pkg in "$@"; do
    if ! opkg list-installed | grep -q "^$pkg"; then
      missing="$missing $pkg"
    fi
  done
  if [ -n "$missing" ]; then
    opkg update && opkg install $missing
    echo ""
  fi
}

script_update() {
  local mode="${1:-interactive}"
  packages_checker curl tar ca-certificates wget-ssl jq
  if opkg update && opkg install "$REPO"; then
    if [ "$mode" = "silent" ]; then
      logger -p notice -t KeenSnap "Пакет обновлён в silent-режиме"
      exit 0
    fi
    print_message "Пакет обновлён" "$GREEN"
    sleep 1
    exec "$KEENSNAP_DIR/$SCRIPT"
  else
    if [ "$mode" = "silent" ]; then
      logger -p err -t KeenSnap "Ошибка при обновлении пакета"
      exit 1
    else
      print_message "Не удалось обновить пакет. Выполните обновление вручную." "$RED"
    fi
  fi
}

cleanup() {
  pkill -P $$ 2>/dev/null
  exit 0
}

if [ "$1" = "script_update" ]; then
  script_update "$2"
else
  setup_config
  main_menu
fi
