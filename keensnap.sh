#!/bin/sh
source /opt/root/KeenSnap/config.sh
RED='\033[1;31m'
GREEN='\033[1;32m'
CYAN='\033[0;36m'
NC='\033[0m'
USERNAME="spatiumstas"
REPO="keensnap"
SCRIPT="keensnap.sh"
TMP_DIR="/tmp"
OPT_DIR="/opt"

KEENSNAP_DIR="/opt/root/KeenSnap"
SNAPD="keensnap-init"
CONFIG_FILE="/opt/root/KeenSnap/config.sh"
PATH_SCHEDULE="/opt/etc/ndm/schedule.d/99-keensnap.sh"
CONFIG_TEMPLATE="config.template"
SCRIPT_VERSION=$(grep -oP 'SCRIPT_VERSION="\K[^"]+' $KEENSNAP_DIR/$SNAPD)

print_menu() {
  printf "\033c"
  printf "${CYAN}"
  cat <<'EOF'
  _  __               ____
 | |/ /___  ___ _ __ / ___| _ __   __ _ _ __
 | ' // _ \/ _ \ '_ \\___ \| '_ \ / _` | '_ \
 | . \  __/  __/ | | |___) | | | | (_| | |_) |
 |_|\_\___|\___|_| |_|____/|_| |_|\__,_| .__/
                                       |_|
EOF
  if [ ! -f $KEENSNAP_DIR/$SNAPD ]; then
    printf "${RED}Конфигурация не настроена${NC}\n\n"
  else
    printf "${RED}Версия скрипта: ${NC}%s\n\n" "$SCRIPT_VERSION by ${USERNAME}"
  fi
  echo "1. Настроить конфигурацию"
  echo "2. Параметры бэкапа"
  echo "3. Подключить Telegram"
  echo "4. Ручной бэкап"
  echo ""
  echo "77. Удалить файлы"
  echo "99. Обновить скрипт"
  echo "00. Выход"
  echo ""
}

main_menu() {
  print_menu
  read -p "Выберите действие: " choice branch
  echo ""
  choice=$(echo "$choice" | tr -d '\032' | tr -d '[A-Z]')

  if [ -z "$choice" ]; then
    main_menu
  else
    case "$choice" in
    1) setup_config ;;
    2) select_backup_options ;;
    3) connect_telegram ;;
    4) manual_backup ;;
    77) remove_script ;;
    99) script_update "main" ;;
    999) script_update "dev" ;;
    00) exit ;;
    *)
      echo "Неверный выбор. Попробуйте снова."
      sleep 1
      main_menu
      ;;
    esac
  fi
}

print_message() {
  message="$1"
  color="${2:-$NC}"
  border=$(printf '%0.s-' $(seq 1 $((${#message} + 2))))
  printf "${color}\n+${border}+\n| ${message} |\n+${border}+\n${NC}\n"
}

exit_function() {
  echo ""
  read -n 1 -s -r -p "Для возврата нажмите любую клавишу..."
  main_menu
}

create_schedule_init() {
  cat <<'EOL' >"$PATH_SCHEDULE"
#!/bin/sh
source /opt/root/KeenSnap/config.sh

if [ "$1" = "start" ] && [ "$schedule" = "$SCHEDULE_NAME" ]; then
  $PATH_SNAPD start "$schedule"
fi
exit 0

EOL
  chmod +x "$PATH_SCHEDULE"
}

select_schedule() {
  message=$1
  schedules=""
  descs=""
  index=1
  schedule_output=$(ndmc -c show sc schedule)

  while IFS= read -r line; do
    if echo "$line" | grep -q "^\s*name:" && ! echo "$line" | grep -q "config"; then
      if [ -n "$current_schedule" ]; then
        if [ -n "$current_desc" ]; then
          echo "$index. $current_schedule ($current_desc)"
        else
          echo "$index. $current_schedule"
        fi
        schedules="$schedules $index:$current_schedule"
        descs="$descs $index:$current_desc"
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
    descs="$descs $index:$current_desc"
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
      exit_function
    fi
  fi

  return 0
}

update_config() {
  silent=$1
  CONFIG_TEMPLATE_URL="https://raw.githubusercontent.com/$USERNAME/$REPO/main/$CONFIG_TEMPLATE"
  TEMP_TEMPLATE_FILE="$TMP_DIR/$CONFIG_TEMPLATE"

  [ -z "$silent" ] && print_message "Обновляю шаблон конфигурации..."

  HTTP_STATUS=$(curl -s -o "$TEMP_TEMPLATE_FILE" -w "%{http_code}" "$CONFIG_TEMPLATE_URL")

  if [ "$HTTP_STATUS" -ne 200 ]; then
    [ -z "$silent" ] && print_message "Не удалось скачать шаблон конфигурации. HTTP-статус: $HTTP_STATUS" "$RED"
    rm -f "$TEMP_TEMPLATE_FILE"
    exit_function
  fi

  config_template=$(cat "$TEMP_TEMPLATE_FILE")

  if [ ! -f "$CONFIG_FILE" ]; then
    [ -z "$silent" ] && print_message "Создаю конфигурационный файл..." "$CYAN"
    {
      mkdir -p "$KEENSNAP_DIR"
      echo "$config_template" >"$CONFIG_FILE"
    } >/dev/null 2>&1
  else
    {
      echo "$config_template" | while IFS= read -r line; do
        param_name=$(echo "$line" | awk -F'=' '{print $1}')
        if ! grep -q "^$param_name=" "$CONFIG_FILE"; then
          echo "$line" >>"$CONFIG_FILE"
        fi
      done
    } >/dev/null 2>&1
  fi

  rm -f "$TEMP_TEMPLATE_FILE"
  create_schedule_init
}

setup_config() {
  update_config

  if [ ! -f "$KEENSNAP_DIR/$SNAPD" ]; then
    curl -L -s "https://raw.githubusercontent.com/$USERNAME/$REPO/main/$SNAPD" --output "$KEENSNAP_DIR/$SNAPD"
    chmod +x "$KEENSNAP_DIR/$SNAPD"
  fi

  if ! select_schedule "Выберите номер расписания:"; then
    exit_function
  fi

  print_message "Вы выбрали: $SCHEDULE_SELECTED" "$CYAN"

  sed -i "s|^SCHEDULE_NAME=.*|SCHEDULE_NAME=\"$SCHEDULE_SELECTED\"|" "$CONFIG_FILE"
  identify_external_drive "Выберите накопитель для бэкапа:"
  sed -i "s|^SELECTED_DRIVE=.*|SELECTED_DRIVE=\"$selected_drive\"|" "$CONFIG_FILE"
  print_message "Вы выбрали: $selected_drive" "$CYAN"

  dos2unix "$CONFIG_FILE"
  print_message "Конфигурация сохранена в $CONFIG_FILE" "$GREEN"
  exit_function
}

get_options() {
  i=1
  for option in $options; do
    value=$(grep "^$option=" "$CONFIG_FILE" | cut -d '=' -f2)
    echo "$i) $option=${value:-false}"
    i=$((i + 1))
  done
}
select_backup_options() {
  check_config
  echo "Текущие параметры:"

  options="BACKUP_STARTUP_CONFIG BACKUP_FIRMWARE BACKUP_ENTWARE BACKUP_WG_PRIVATE_KEY DELETE_ARCHIVE_AFTER_BACKUP SEND_BACKUP_TG"
  get_options
  echo ""
  read -p "Выберите, какие параметры изменить, разделяя их пробелом: " user_choice

  for choice in $user_choice; do
    if [ "$choice" -ge 1 ] && [ "$choice" -le $(echo "$options" | wc -w) ]; then
      selected_option=$(echo "$options" | cut -d' ' -f"$choice")
      current_value=$(grep "^$selected_option=" "$CONFIG_FILE" | cut -d '=' -f2)

      if [ "$current_value" = "true" ]; then
        sed -i "s/^$selected_option=.*/$selected_option=false/" "$CONFIG_FILE"
      else
        sed -i "s/^$selected_option=.*/$selected_option=true/" "$CONFIG_FILE"
      fi
    else
      echo "Неверный выбор: $choice."
      exit_function
    fi
  done

  print_message "Настройки обновлены" "$GREEN"
  echo "Новые параметры:"
  get_options
  exit_function
}

connect_telegram() {
  check_config
  read -p "Введите токен бота Telegram: " BOT_TOKEN
  BOT_TOKEN=$(echo "$BOT_TOKEN" | sed 's/^[ \t]*//;s/[ \t]*$//')
  read -p "Введите ID пользователя/чата Telegram: " CHAT_ID
  CHAT_ID=$(echo "$CHAT_ID" | sed 's/^[ \t]*//;s/[ \t]*$//')
  sed -i "s|^BOT_TOKEN=.*|BOT_TOKEN=\"$BOT_TOKEN\"|" "$CONFIG_FILE"
  sed -i "s|^CHAT_ID=.*|CHAT_ID=\"$CHAT_ID\"|" "$CONFIG_FILE"

  dos2unix "$CONFIG_FILE"
  print_message "Конфигурация сохранена в $CONFIG_FILE" "$GREEN"
  exit_function
}

check_config() {
  if [ ! -f "$CONFIG_FILE" ]; then
    print_message "Не выполнена начальная конфигурация" "$RED"
    exit_function
  fi
}

manual_backup() {
  $KEENSNAP_DIR/$SNAPD start manual
  exit_function
}

identify_external_drive() {
  local message=$1
  local message2=$2
  local special_message=$3
  labels=""
  uuids=""
  index=1
  media_found=0
  media_output=$(ndmc -c show media)
  current_manufacturer=""

  if [ -z "$media_output" ]; then
    print_message "Не удалось получить список накопителей" "$RED"
    return 1
  fi

  echo "0. Встроенное хранилище (может не хватить места) $message2"

  while IFS= read -r line; do
    case "$line" in
    *"name: Media"*)
      media_found=1
      current_manufacturer=""
      ;;
    *"manufacturer:"*)
      if [ "$media_found" = "1" ]; then
        current_manufacturer=$(echo "$line" | cut -d ':' -f2- | sed 's/^ *//g')
      fi
      ;;
    *"uuid:"*)
      if [ "$media_found" = "1" ]; then
        uuid=$(echo "$line" | cut -d ':' -f2- | sed 's/^ *//g')
        read -r label_line
        read -r fstype_line
        read -r state_line
        read -r total_line
        read -r free_line

        label=$(echo "$label_line" | cut -d ':' -f2- | sed 's/^ *//g')
        fstype=$(echo "$fstype_line" | cut -d ':' -f2- | sed 's/^ *//g')
        free_bytes=$(echo "$free_line" | cut -d ':' -f2- | sed 's/^ *//g')

        if [ "$fstype" = "swap" ]; then
          uuid=""
          continue
        fi

        free_mb=$((free_bytes / 1024 / 1024))
        free_gb=$((free_mb / 1024))

        if [ "$free_mb" -lt 1024 ]; then
          free_display="$free_mb"
          unit="MB"
        else
          free_display="$free_gb"
          unit="GB"
        fi

        if [ -n "$label" ]; then
          display_name="$label"
        elif [ -n "$current_manufacturer" ]; then
          display_name="$current_manufacturer"
        else
          display_name="Unknown"
        fi

        echo "$index. $display_name ($fstype, ${free_display}${unit})"
        labels="$labels \"$display_name\""
        uuids="$uuids $uuid"
        index=$((index + 1))
        uuid=""
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
    selected_drive=$(echo "$uuids" | awk -v choice="$choice" '{split($0, a, " "); print a[choice]}')
    if [ -z "$selected_drive" ]; then
      print_message "Неверный выбор" "$RED"
      exit_function
    fi
    selected_drive="/tmp/mnt/$selected_drive"
  fi
}

remove_script() {
  echo "Удаляю хук $KEENSNAP_DIR/$SNAPD..."
  rm -r "$KEENSNAP_DIR/$SNAPD" 2>/dev/null

  print_message "Успешно удалено" "$GREEN"
  exit_function
}

packages_checker() {
  if ! opkg list-installed | grep -q "^curl"; then
    opkg update && opkg install curl
    echo ""
  fi
}

script_update() {
  BRANCH="$1"
  packages_checker
  curl -L -s "https://raw.githubusercontent.com/$USERNAME/$REPO/$BRANCH/$SCRIPT" --output $TMP_DIR/$SCRIPT
  curl -L -s "https://raw.githubusercontent.com/$USERNAME/$REPO/$BRANCH/$SNAPD" --output $KEENSNAP_DIR/$SNAPD
  chmod +x $KEENSNAP_DIR/$SNAPD

  if [ -f "$TMP_DIR/$SCRIPT" ]; then
    mv "$TMP_DIR/$SCRIPT" "$KEENSNAP_DIR/$SCRIPT"
    chmod +x $KEENSNAP_DIR/$SCRIPT
    if [ ! -f "$OPT_DIR/bin/$REPO" ]; then
      cd $OPT_DIR/bin
      ln -s "$KEENSNAP_DIR/$SCRIPT" "$OPT_DIR/bin/$REPO"
    fi
    if [ "$BRANCH" = "dev" ]; then
      print_message "Скрипт успешно обновлён на $BRANCH ветку..." "$GREEN"
    else
      print_message "Скрипт успешно обновлён" "$GREEN"
    fi
    sleep 1
    $KEENSNAP_DIR/$SCRIPT
    update_config 1
    main_menu
  else
    print_message "Ошибка при скачивании скрипта" "$RED"
  fi
}

if [ "$1" = "script_update" ]; then
  script_update "main"
else
  main_menu
fi
