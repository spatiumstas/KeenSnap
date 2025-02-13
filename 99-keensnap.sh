#!/bin/sh

source /opt/root/KeenSnap/config.sh

SCRIPT_VERSION="v1.0"
SCHEDULE_ID="$schedule"
PATH_SNAPD="/opt/etc/ndm/schedule.d/99-keensnap.sh"
PATH_SYMBOLIC="/opt/root/KeenSnap/99-keensnap.sh"
REMOTE_VERSION=$(curl -s "https://api.github.com/repos/spatiumstas/keensnap/releases/latest" | grep -Po '"tag_name": "\K.*?(?=")')
date="backup$(date +%Y-%m-%d_%H-%M-%S)"
items=""
statuses=""

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $*" | tee -a "$LOG_FILE"
}

error() {
  echo -e "$(date '+%Y-%m-%d %H:%M:%S') \033[1;31m[ERROR]\033[0m $*" | tee -a "$LOG_FILE"
}

success() {
  echo -e "$(date '+%Y-%m-%d %H:%M:%S') \033[1;32m[SUCCESS]\033[0m $*" | tee -a "$LOG_FILE"
}

get_device_info() {
  local version_output
  version_output=$(ndmc -c show version 2>/dev/null)

  DEVICE=$(echo "$version_output" | grep "device" | awk -F": " '{print $2}')
  FW_VERSION=$(echo "$version_output" | grep "title" | awk -F": " '{print $2}')
  DEVICE_ID=$(echo "$version_output" | grep "hw_id" | awk -F": " '{print $2}')

  if [ -z "$DEVICE" ] || [ -z "$FW_VERSION" ] || [ -z "$DEVICE_ID" ]; then
    log "Ошибка при получении информации о устройстве."
    exit 1
  fi
}

clean_log() {
  local log_file="$1"
  local max_size=524288

  if [ ! -f $log_file ]; then
    touch $log_file
  fi

  local current_size=$(wc -c <"$log_file")
  if [ $current_size -gt $max_size ]; then
    sed -i '1,100d' "$log_file"
    log "Лог-файл был обрезан на первые 100 строк."
  fi
}

send_to_telegram() {
  if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
    log "Токен бота или ID чата не заданы. Отправка в Telegram пропущена."
    return 1
  fi

  local chat_id="${CHAT_ID%%_*}"
  local topic_id="${CHAT_ID#*_}"
  if [ "$chat_id" = "$CHAT_ID" ]; then
    topic_id=""
  fi

  local caption="$1"
  local file_path="$2"

  local escaped_caption
  escaped_caption=$(echo "$caption" | sed 's/[][*_`]/\\&/g')

  if [ -n "$file_path" ] && [ -f "$file_path" ]; then
    local response
    response=$(curl -s -o /dev/null -w "%{http_code}" -F "chat_id=$chat_id" \
      -F "document=@$file_path" \
      -F "caption=$escaped_caption" \
      -F "parse_mode=Markdown" \
      https://api.telegram.org/bot$BOT_TOKEN/sendDocument)
  else
    local payload
    if [ -n "$topic_id" ]; then
      payload=$(printf '{"chat_id":%s,"message_thread_id":%s,"parse_mode":"Markdown","text":"%s"}' \
        "$chat_id" "$topic_id" "$escaped_caption")
    else
      payload=$(printf '{"chat_id":%s,"parse_mode":"Markdown","text":"%s"}' \
        "$chat_id" "$escaped_caption")
    fi
    local response
    response=$(curl -s -o /dev/null -w "%{http_code}" -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
      -H "Content-Type: application/json" \
      -d "$payload")
  fi

  if [ "$response" -eq 200 ]; then
    success "Сообщение успешно отправлено в Telegram."
    return 0
  else
    error "Ошибка отправки в Telegram (HTTP $response)."
    return 1
  fi
}

backup_startup_config() {
  local success=1
  local item_name="startup-config"
  if [ -n "$SELECTED_DRIVE" ]; then
    local device_uuid=$(echo "$SELECTED_DRIVE" | awk -F'/' '{print $NF}')
    local folder_path="$device_uuid:/$date"
    local backup_file="$folder_path/${FW_VERSION}_$item_name.txt"
    ndmc -c "copy $item_name $backup_file"
    if [ $? -eq 0 ]; then
      success "$item_name сохранён"
      success=0
    else
      error "Ошибка при сохранении $item_name"
    fi
  fi
  items="$items $item_name"
  statuses="$statuses $success"
}

backup_entware() {
  local success=1
  local item_name="Entware"
  if [ -n "$SELECTED_DRIVE" ]; then
    local backup_file="$SELECTED_DRIVE/$date/$item_name.tar.gz"
    tar cvzf "$backup_file" -C /opt . >/dev/null 2>&1
    if [ $? -eq 0 ]; then
      success "$item_name сохранён"
      success=0
    else
      error "Ошибка при сохранении $item_name"
    fi
  fi
  items="$items $item_name"
  statuses="$statuses $success"
}

backup_wg_private_key() {
  local success=1
  local item_name="WireGuard-Private-Key"
  if opkg list-installed | grep -q "^wireguard-tools"; then
    if [ -n "$SELECTED_DRIVE" ]; then
      local folder_path="$SELECTED_DRIVE/$date"
      local backup_file="$folder_path/$item_name.txt"
      wg show all private-key >"$backup_file"
      if [ $? -eq 0 ]; then
        success "$item_name сохранён"
        success=0
      else
        error "Ошибка при сохранении $item_name"
      fi
      items="$items $item_name"
      statuses="$statuses $success"
    fi
  fi
}

backup_firmware() {
  local success=1
  local item_name="firmware"
  if [ -n "$SELECTED_DRIVE" ]; then
    local device_uuid=$(echo "$SELECTED_DRIVE" | awk -F'/' '{print $NF}')
    local folder_path="$device_uuid:/$date"
    local backup_file="$folder_path/${DEVICE_ID}_${FW_VERSION}_$item_name.bin"
    ndmc -c "copy flash:/$item_name $backup_file"
    if [ $? -eq 0 ]; then
      success "$item_name сохранена"
      success=0
    else
      error "Ошибка при сохранении $item_name"
    fi
  fi
  items="$items $item_name"
  statuses="$statuses $success"
}

create_backup_and_send_report() {
  local items=""
  local statuses=""
  mkdir -p "$SELECTED_DRIVE/$date"
  local backup_performed=0

  if [ "$BACKUP_STARTUP_CONFIG" = "true" ]; then
    backup_startup_config
    backup_performed=1
  fi

  if [ "$BACKUP_FIRMWARE" = "true" ]; then
    backup_firmware
    backup_performed=1
  fi

  if [ "$BACKUP_ENTWARE" = "true" ]; then
    backup_entware
    backup_performed=1
  fi

  if [ "$BACKUP_WG_PRIVATE_KEY" = "true" ]; then
    backup_wg_private_key
    backup_performed=1
  fi

  if [ "$backup_performed" -eq 0 ]; then
    log "Ни один из вариантов бэкапа не выбран"
    return 1
  fi

  local archive_path
  if [ -n "$SELECTED_DRIVE" ] && [ -d "$SELECTED_DRIVE/$date" ]; then
    archive_path="$SELECTED_DRIVE/${DEVICE_ID}_$date.tar.gz"
    tar -czf "$archive_path" -C "$SELECTED_DRIVE" "$date"
    if [ $? -ne 0 ]; then
      error "Ошибка при создании архива."
      return 1
    fi
    log "Архив создан: $archive_path"
  else
    error "Невозможно создать архив: папка с бэкапами не найдена."
    return 1
  fi

  local report="Бэкап $DEVICE_ID ($(date)) выполнен:"$'\n\n'
  local i=1
  for item in $items; do
    local status_value=$(echo $statuses | cut -d' ' -f$i)
    if [ "$status_value" -eq 0 ]; then
      report="$report✅ $item"$'\n'
    else
      report="$report❌ $item"$'\n'
    fi
    i=$((i + 1))
  done

  send_to_telegram "$report" "$archive_path"
  rm -rf "$SELECTED_DRIVE/$date"
  rm -rf "$archive_path"
  log "Временные файлы удалены"
}

main() {
  clean_log "$LOG_FILE"
  get_device_info
  if [ "$1" = "start" ] && [ "$schedule" = $SCHEDULE_NAME ]; then

    log "Запуск скрипта для расписания $schedule"
    create_backup_and_send_report
    log "Скрипт завершил работу"
  else
    exit 0
  fi
}

check_update() {
  local local_num=$(echo "${SCRIPT_VERSION#v}" | awk -F. '{print $1*10000 + $2*100 + $3}')
  local remote_num=$(echo "${REMOTE_VERSION#v}" | awk -F. '{print $1*10000 + $2*100 + ($3 == "" ? 0 : $3)}')

  if [ "$remote_num" -gt "$local_num" ]; then
    log "Доступна новая версия: $REMOTE_VERSION. Обновляюсь..."
    keensnap "script_update"
  fi
}

main "$@"
check_update
