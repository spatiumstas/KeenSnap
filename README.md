# Бэкап конфигурации KeeneticOS
<img src="https://github.com/user-attachments/assets/789cf6e7-848f-44dc-804c-38f84e65c5d5" alt="" width="700">

## Работа сервиса
- Выбор объектов бэкапа состоит из: `Startup-Config`, `Entware`, `Firmware` и `WireGuard Private-Keys`
- Полученный архив с копией устройства можно сохранить/отправить в Telegram и/или смонтированный раздел (внешний накопитель/WebDav).
- При срабатывании расписания запускается хук `/opt/etc/ndm/schedule.d/99-keensnap.sh`
- Просмотр логов: `cat /opt/var/log/keensnap.log` или журнале KeeneticOS. Они также сохраняются в каждом созданном архиве.

## Установка:

1. В `SSH` ввести команду
```shell
opkg update && opkg install curl && curl -L -s "https://raw.githubusercontent.com/spatiumstas/keensnap/main/install.sh" > /tmp/install.sh && sh /tmp/install.sh
```

2. В скрипте выбрать настройку

- Ручной запуска скрипта через `keensnap` или `/opt/root/KeenSnap/keensnap.sh`

# Настройка
1. Иметь настроенное расписание, созданное через веб-интерфейс [KeeneticOS](https://support.keenetic.ru/giga/kn-1010/ru/22348-disabling-all-leds-on-schedule.html). Вешать его на что-либо необязательно.
2. После запуска скрипта выбрать `Настроить конфигурацию`. В предложенном списке выбрать нужное расписание для частоты бэкапа. При первом запуске создастся файл конфигурации, в дальнейшем в нём записываются все настройки. Также скрипт спросит, где сохранять архив с копией устройства.
3. Перейти в `Параметры бэкапа` и выбрать нужные параметры.
4. В разделе `Подключить Telegram` можно указать данные, необходимые для отправки архива.

## Подключение Telegram

1. Получить и скопировать `ID` своего аккаунта или чата через [UserInfoBot](https://t.me/userinfobot)
2. Создать своего бота через [BotFather](https://t.me/BotFather) и скопировать его `token`

<img src="https://github.com/user-attachments/assets/ca5c31af-b29c-4d5a-b2d9-75ff64ba2c34" alt="" width="700">

3. Вставить в скрипт

   <img src="https://github.com/user-attachments/assets/632f2c6c-0b53-4502-8c6e-0e4c44cfe65b" alt="" width="700">
