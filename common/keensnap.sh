#!/bin/sh
trap cleanup HUP INT TERM EXIT
CONFIG_FILE="/opt/root/KeenSnap/config.conf"
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"
SYSTEM_LD_LIBRARY_PATH="/lib:/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
OPKG_LD_LIBRARY_PATH="/opt/lib:/opt/usr/lib:/lib:/usr/lib"
export LD_LIBRARY_PATH="$OPKG_LD_LIBRARY_PATH"
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

format_upload_methods() {
  local methods="$1"
  [ -n "$methods" ] && echo "$methods" || echo "Telegram"
}

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
  if [ ! -f $KEENSNAP_DIR/$SNAPD ]; then
    printf "${RED}Конфигурация не настроена${NC}\n\n"
  else
    current_upload_methods=$(format_upload_methods "$(get_config_value "UPLOAD_METHOD")")
    printf "${CYAN}Модель:         ${NC}%s\n" "$(get_device) ($(get_hw_id)) | $(get_fw_version)"
    printf "${CYAN}Накопитель:     ${NC}%s\n" "$SELECTED_DRIVE"
    printf "${CYAN}Отправка:       ${NC}%s\n" "$current_upload_methods"
    printf "${CYAN}Версия:         ${NC}%s\n\n" "$SCRIPT_VERSION by ${USERNAME}"
  fi
  echo "1. Запустить бэкап"
  echo "2. Параметры"
  echo "3. Показать конфиг"
  echo "4. Показать логи"
  printf "\n88. Удалить скрипт\n"  
  echo "99. Обновить скрипт"
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
    88) remove_script ;;
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

rci_request() {
  local endpoint="$1"
  curl -s "http://localhost:79/rci/$endpoint"
}

rci_parse() {
  local command="$1"
  curl -fsS -H "Content-Type: application/json" \
    -d "[{\"parse\":\"$command\"}]" \
    "http://localhost:79/rci/"
}

ndmc_cli() {
  LD_LIBRARY_PATH="$SYSTEM_LD_LIBRARY_PATH" ndmc -c "$@"
}

get_device() {
  rci_request "show/version" | grep -o '"device": "[^"]*"' | cut -d'"' -f4 2>/dev/null
}

get_fw_version() {
  rci_request "show/version" | grep -o '"title": "[^"]*"' | cut -d'"' -f4 2>/dev/null
}

get_hw_id() {
  rci_request "show/version" | grep -o '"hw_id": "[^"]*"' | cut -d'"' -f4 2>/dev/null
}

select_schedule() {
  message=$1
  schedules=""
  index=1
  schedule_output=$(ndmc_cli show sc schedule)

  while IFS= read -r line; do
    if echo "$line" | grep -q "^\s*name:" && ! echo "$line" | grep -q "config"; then
      if [ -n "$current_schedule" ]; then
        if [ -n "$current_desc" ]; then
          echo "$index. $current_schedule ($current_desc)"
        else
          echo "$index. $current_schedule"
        fi
        schedules="$schedules $index:$current_schedule"
        index=$((index + 1))
      fi
      current_schedule=$(echo "$line" | cut -d ':' -f2- | sed 's/^ *//g')
      current_desc=""
    fi

    if echo "$line" | grep -q "^\s*description:"; then
      current_desc=$(echo "$line" | cut -d ':' -f2- | sed 's/^ *//g')
    fi
  done <<EOF
$schedule_output
EOF

  if [ -n "$current_schedule" ]; then
    if [ -n "$current_desc" ]; then
      echo "$index. $current_schedule ($current_desc)"
    else
      echo "$index. $current_schedule"
    fi
    schedules="$schedules $index:$current_schedule"
  fi

  if [ -z "$schedules" ]; then
    print_message "Расписания не найдены" "$RED"
  else

    echo ""
    read -p "$message " choice
    choice=$(echo "$choice" | tr -d ' \n\r')

    SCHEDULE_SELECTED=$(echo "$schedules" | tr ' ' '\n' | grep "^$choice:" | cut -d ':' -f2)
    if [ -z "$SCHEDULE_SELECTED" ]; then
      print_message "Неверный выбор" "$RED"
      return 1
    fi
    print_message "Вы выбрали: $SCHEDULE_SELECTED" "$CYAN"
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

set_config_value() {
  local key="$1"
  local value="$2"
  if grep -q "^$key=" "$CONFIG_FILE" 2>/dev/null; then
    sed -i "s|^$key=.*|$key=\"$value\"|" "$CONFIG_FILE"
  else
    echo "$key=\"$value\"" >>"$CONFIG_FILE"
  fi
}

set_config_number() {
  local key="$1"
  local value="$2"
  if grep -q "^$key=" "$CONFIG_FILE" 2>/dev/null; then
    sed -i "s|^$key=.*|$key=$value|" "$CONFIG_FILE"
  else
    echo "$key=$value" >>"$CONFIG_FILE"
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
    print_message "Конфиг не найден. Переустановите пакет $REPO" "$RED"
    return 1
  fi

  dos2unix "$CONFIG_FILE" >/dev/null 2>&1
}

setup_schedule() {
  setup_config || return 1
  if ! select_schedule "Выберите номер расписания:"; then
    return 1
  fi
  sed -i "s|^SCHEDULE_NAME=.*|SCHEDULE_NAME=\"$SCHEDULE_SELECTED\"|" "$CONFIG_FILE"
  if ! select_drive "Выберите накопитель для бэкапа:"; then
    return 1
  fi
  sed -i "s|^SELECTED_DRIVE=.*|SELECTED_DRIVE=\"$selected_drive\"|" "$CONFIG_FILE"
  print_message "Вы выбрали: $selected_drive" "$CYAN"

  dos2unix "$CONFIG_FILE"
  print_message "Конфигурация сохранена в $CONFIG_FILE" "$GREEN"
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
      echo "$key=false" >>"$CONFIG_FILE"
    fi
  else
    if grep -q "^$key=" "$CONFIG_FILE" 2>/dev/null; then
      sed -i "s/^$key=.*/$key=true/" "$CONFIG_FILE"
    else
      echo "$key=true" >>"$CONFIG_FILE"
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
  current_method=$(get_config_value "UPLOAD_METHOD")
  [ -z "$current_method" ] && current_method="Telegram"
  printf "Текущий способ: %s\n\n" "$(format_upload_methods "$current_method")"
  echo "Введите номера через пробел (допустимо несколько):"
  echo "1. Telegram"
  echo "2. Google Drive"
  echo ""
  read -p "Выбор: " upload_choice

  local selected_methods=""
  for choice in $upload_choice; do
    case "$choice" in
      1) selected_methods="$selected_methods Telegram" ;;
      2) selected_methods="$selected_methods GDrive" ;;
    esac
  done

  selected_methods=$(echo "$selected_methods" | tr ' ' '\n' | sed '/^$/d' | awk '!seen[$0]++ { if (out) out=out","$0; else out=$0 } END { print out }')
  [ -z "$selected_methods" ] && selected_methods="$current_method"
  set_config_value "UPLOAD_METHOD" "$selected_methods"
  UPLOAD_METHOD="$selected_methods"
  dos2unix "$CONFIG_FILE"
  print_message "Способ загрузки обновлён" "$GREEN"
}

setup_telegram_settings() {
  check_config
  current_token=$(get_config_value "BOT_TOKEN")
  current_chat=$(get_config_value "CHAT_ID")
  current_proxy_interface=$(get_config_value "PROXY_INTERFACE")
  current_proxy_url=$(get_config_value "TG_PROXY")

  read -p "BOT_TOKEN (Enter = оставить, '-' = очистить): " value
  if [ "$value" = "-" ]; then
    current_token=""
  elif [ -n "$value" ]; then
    current_token="$value"
  fi

  read -p "CHAT_ID (Enter = оставить, '-' = очистить): " value
  if [ "$value" = "-" ]; then
    current_chat=""
  elif [ -n "$value" ]; then
    current_chat="$value"
  fi

  read -p "PROXY_INTERFACE (например nwg0, Enter = оставить, '-' = очистить): " value
  if [ "$value" = "-" ]; then
    current_proxy_interface=""
  elif [ -n "$value" ]; then
    current_proxy_interface="$value"
  fi

  read -p "TG_PROXY URL (например socks5://127.0.0.1:1080, Enter = оставить, '-' = очистить): " value
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

  read -p "GD_CLIENT_ID (Enter = оставить, '-' = очистить): " value
  if [ "$value" = "-" ]; then
    gd_id=""
  elif [ -n "$value" ]; then
    gd_id="$value"
  fi

  read -p "GD_CLIENT_SECRET (Enter = оставить, '-' = очистить): " value
  if [ "$value" = "-" ]; then
    gd_secret=""
  elif [ -n "$value" ]; then
    gd_secret="$value"
  fi

  read -p "GD_REFRESH_TOKEN (Enter = оставить, '-' = очистить): " value
  if [ "$value" = "-" ]; then
    gd_refresh=""
  elif [ -n "$value" ]; then
    gd_refresh="$value"
  fi

  read -p "GD_FOLDER_ID (Enter = оставить, '-' = очистить): " value
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

setup_runtime_settings() {
  check_config
  retain_days=$(get_config_raw "RETAIN_ARCHIVES_DAYS")
  auto_update=$(get_config_raw "AUTO_UPDATE")
  delete_archive=$(get_config_raw "DELETE_LOCAL_ARCHIVE_AFTER_BACKUP")

  printf "1. AUTO_UPDATE=$auto_update\n"
  printf "2. RETAIN_ARCHIVES_DAYS=$retain_days\n"
  printf "3. DELETE_LOCAL_ARCHIVE_AFTER_BACKUP=$delete_archive\n\n"
  read -p "Выберите параметр: " setting_choice

  case "$setting_choice" in
    1)
      toggle_boolean_option "AUTO_UPDATE"
      ;;
    2)
      read -p "Введите число дней хранения локальных архивов (0 - отключить): " value
      if echo "$value" | grep -Eq '^[0-9]+$'; then
        set_config_number "RETAIN_ARCHIVES_DAYS" "$value"
      fi
      ;;
    3)
      toggle_boolean_option "DELETE_LOCAL_ARCHIVE_AFTER_BACKUP"
      ;;
  esac

  dos2unix "$CONFIG_FILE"
  print_message "Параметры обновлены" "$GREEN"
}

setup_backup_content() {
  check_config
  while true; do
    printf "Состав бэкапа:\n\n"
    echo "1) BACKUP_STARTUP_CONFIG=$(get_config_bool "BACKUP_STARTUP_CONFIG" "false")"
    echo "2) BACKUP_FIRMWARE=$(get_config_bool "BACKUP_FIRMWARE" "false")"
    echo "3) BACKUP_ENTWARE=$(get_config_bool "BACKUP_ENTWARE" "false")"
    echo "4) BACKUP_WG_PRIVATE_KEY=$(get_config_bool "BACKUP_WG_PRIVATE_KEY" "false")"
    printf "0) Назад\n\n"
    read -p "Выберите параметр для переключения: " backup_choice
    echo ""

    case "$backup_choice" in
      1) toggle_boolean_option "BACKUP_STARTUP_CONFIG" ;;
      2) toggle_boolean_option "BACKUP_FIRMWARE" ;;
      3) toggle_boolean_option "BACKUP_ENTWARE" ;;
      4) toggle_boolean_option "BACKUP_WG_PRIVATE_KEY" ;;
      0) break ;;
      *) echo "Неверный выбор" ;;
    esac
    dos2unix "$CONFIG_FILE"
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
    echo "5. Состав бэкапа"
    echo "6. Автоудаление и обновление"
    echo "0. Назад"
    echo ""
    read -p "Выберите действие: " action
    echo ""
    case "$action" in
      1) setup_schedule ;;
      2) setup_upload_method ;;
      3) setup_telegram_settings ;;
      4) setup_google_drive_settings ;;
      5) setup_backup_content ;;
      6) setup_runtime_settings ;;
      0) break ;;
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

select_drive_extract_value() {
  echo "$1" | cut -d ':' -f2- | sed 's/^[[:space:]]*//; s/[",]//g'
}

select_drive_reset_partition() {
  in_partition=0
  uuid=""
  label=""
  fstype=""
  total_bytes=""
  free_bytes=""
}

select_drive_reset_media() {
  media_found=1
  media_is_usb=0
  current_manufacturer=""
  select_drive_reset_partition
}

select_drive_add_partition() {
  local used_bytes display_name fstype_upper

  if [ -z "$uuid" ] || [ -z "$fstype" ] || [ "$(echo "$fstype" | tr '[:upper:]' '[:lower:]')" = "swap" ]; then
    select_drive_reset_partition
    return
  fi

  echo "$total_bytes" | grep -qE '^[0-9]+$' || total_bytes=0
  echo "$free_bytes" | grep -qE '^[0-9]+$' || free_bytes=0

  used_bytes=$((total_bytes - free_bytes))
  [ "$used_bytes" -lt 0 ] && used_bytes=0

  if [ -n "$label" ]; then
    display_name="$label"
  elif [ -n "$current_manufacturer" ]; then
    display_name="$current_manufacturer"
  else
    display_name="Unknown"
  fi

  fstype_upper=$(echo "$fstype" | tr '[:lower:]' '[:upper:]')
  echo "$index. $display_name ($fstype_upper, $(format_size $used_bytes $total_bytes))"
  if [ -n "$uuids" ]; then
    uuids="$uuids
$uuid"
  else
    uuids="$uuid"
  fi
  index=$((index + 1))
  select_drive_reset_partition
}

select_drive() {
  local message="$1"
  local value

  uuids=""
  index=1
  media_found=0
  media_is_usb=0
  media_output=$(rci_parse "show media")
  current_manufacturer=""
  select_drive_reset_partition

  if [ -z "$media_output" ]; then
    print_message "Не удалось получить список накопителей" "$RED"
    return 1
  fi

  echo "0. Встроенное хранилище (может не хватить места) $message2"

  while IFS= read -r line; do
    value=$(select_drive_extract_value "$line")
    case "$line" in
    *"\"Media"*"\":"* | *"name: Media"*)
      select_drive_reset_media
      ;;
    *"\"usb\":"* | *"usb:"*)
      if [ "$media_found" = "1" ]; then
        media_is_usb=1
      fi
      ;;
    *"\"bus\":"* | *"bus:"*)
      if [ "$media_found" = "1" ] && [ "$value" = "usb" ]; then
        media_is_usb=1
      fi
      ;;
    *"\"manufacturer\":"* | *"manufacturer:"*)
      if [ "$media_found" = "1" ]; then
        current_manufacturer="$value"
      fi
      ;;
    *"\"uuid\":"* | *"uuid:"*)
      if [ "$media_found" = "1" ] && [ "$media_is_usb" = "1" ]; then
        select_drive_reset_partition
        in_partition=1
        uuid="$value"
      fi
      ;;
    *"\"label\":"* | *"label:"*)
      [ "$in_partition" = "1" ] && label="$value"
      ;;
    *"\"fstype\":"* | *"fstype:"*)
      [ "$in_partition" = "1" ] && fstype="$value"
      ;;
    *"\"total\":"* | *"total:"*)
      [ "$in_partition" = "1" ] && total_bytes="$value"
      ;;
    *"\"free\":"* | *"free:"*)
      if [ "$in_partition" = "1" ]; then
        free_bytes="$value"
        select_drive_add_partition
      fi
      ;;
    esac
  done <<EOF
$media_output
EOF

  echo ""
  read -p "$message " choice
  choice=$(echo "$choice" | tr -d ' \n\r')
  echo ""
  if [ "$choice" = "0" ]; then
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
        eval "selected_drive=\"\${$folder_choice}\""
      elif [ "$folder_choice" = "00" ] && [ "$selected_drive" != "/tmp/mnt/$uuid" ]; then
        selected_drive=$(dirname "$selected_drive")
      else
        echo "Неверный выбор. Попробуйте снова."
      fi
    done
  fi
}

remove_script() {
  echo "Удаляю все файлы и выхожу из скрипта..."
  rm -rf "$KEENSNAP_DIR" 2>/dev/null
  rm -f "$PATH_SCHEDULE" 2>/dev/null
  rm -f "$OPT_DIR/bin/$REPO" 2>/dev/null

  print_message "Успешно удалено" "$GREEN"
  cleanup
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
  packages_checker curl tar ca-certificates wget-ssl
  ensure_ipk_repo_file
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
