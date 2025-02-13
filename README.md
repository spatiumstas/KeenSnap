# Установка:

1. В `SSH` ввести команду
```shell
opkg update && opkg install curl && curl -L -s "https://raw.githubusercontent.com/spatiumstas/keensnap/main/install.sh" > /tmp/install.sh && sh /tmp/install.sh
```

2. В скрипте выбрать настройку

- Ручной запуска скрипта через `keensnap` или `./KeenSnap/KeenSnap.sh `

# Настройка
1. Иметь настроенное расписание, созданное через веб-интерфейс [KeeneticOS](https://docs.keenetic.com/eaeu/giga/kn-1010/ru/22348-disabling-all-leds-on-schedule.html). Вешать его на что-либо необязательно.
2. После запуска скрипта выбрать `Настроить конфигурацию`. В предложенном списке выбрать нужное расписание для частоты бэкапа. При первом запуске создастся файл конфигурации, в дальнейшем в нём записываются все настройки. Также скрипт спросит, куда сохранять временные файлы.
3. Перейти в `Настроить тип бэкапа` и выбрать нужные параметры. Для WG_PRIVATE_KEY необходим пакет wireguard-tools
4. В разделе `Подключить Telegram` указать данные, необходимые для отправки

# Подключение Telegram

1. Получить и скопировать `ID` своего аккаунта или чата через [UserInfoBot](https://t.me/userinfobot)
2. Создать своего бота через [BotFather](https://t.me/BotFather) и скопировать  его `token`

<img src="https://github.com/user-attachments/assets/ca5c31af-b29c-4d5a-b2d9-75ff64ba2c34" alt="" width="700">

3. Вставить в скрипт
   
   <img src="https://github.com/user-attachments/assets/8f0557ee-b8f1-4636-b8e8-0d3868b5e7a3" alt="" width="700">

# Работа сервиса
- При срабатывании расписания запускается хук `/opt/etc/ndm/schedule.d/99-keensnap.sh`
- Просмотр логов: `cat /opt/root/KeenSnap/log.txt`
