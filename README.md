# Configuration backup KeeneticOS
<img src="https://github.com/user-attachments/assets/789cf6e7-848f-44dc-804c-38f84e65c5d5" alt="" width="700">

## Service operation
- The selection of backup objects consists of: `Startup-Config`, `Entware`, `Firmware` и `WireGuard Private-Keys`
- The resulting archive with a copy of the device can be saved/Sent To Telegram и/or mounted partition ("External storage"/WebDav).
- When the schedule is triggered, a hook is launched `/opt/etc/ndm/schedule.d/99-keensnap.sh`
- View application logs: `cat /opt/var/log/keensnap.log` or log KeeneticOS. They are also stored in each archive created.

## Installation:

1. B `SSH` enter command
```shell
opkg update && opkg install curl && curl -L -s "https://raw.githubusercontent.com/spatiumstas/keensnap/main-english/install.sh" > /tmp/install.sh && sh /tmp/install.sh
```

2. In the script, select the setting

- Manually run the script via `keensnap` Or `/opt/root/KeenSnap/keensnap.sh`

# Setup
1. Have a customized schedule created through the web interface [KeeneticOS](https://support.keenetic.ru/giga/kn-1010/ru/22348-disabling-all-leds-on-schedule.html). It is not necessary to hang it on anything.
2. After running the script, select `Configure`. In the proposed list, select the desired schedule for the backup frequency. At the first start, a configuration file will be created, in the future all settings will be recorded in it. Also, the script will ask where to save the archive with a copy of the device.
3. Go to `Backup Options` and select the desired parameters.
4. In section `Connect Telegram` you can specify the data required to send the archive.

## Connection Telegram

1. Receive & Copy `ID` your account or chat via [UserInfoBot](https://t.me/userinfobot)
2. Create your bot in [BotFather](https://t.me/BotFather) and copy it `token`

<img src="https://github.com/user-attachments/assets/ca5c31af-b29c-4d5a-b2d9-75ff64ba2c34" alt="" width="700">

3. Insert into Script

   <img src="https://github.com/user-attachments/assets/632f2c6c-0b53-4502-8c6e-0e4c44cfe65b" alt="" width="700">
