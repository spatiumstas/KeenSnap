# Бэкап конфигурации KeeneticOS
<img src="https://github.com/user-attachments/assets/789cf6e7-848f-44dc-804c-38f84e65c5d5" alt="" width="700">

## Работа сервиса
- Выбор объектов бэкапа состоит из: `Startup-Config`, `Entware`, `Firmware` и `WireGuard Private-Keys`
- Полученный архив с копией устройства можно сохранить/отправить в Telegram/GoogleDrive и/или смонтированный раздел (внешний накопитель/WebDav).
- При срабатывании расписания запускается хук `/opt/etc/ndm/schedule.d/99-keensnap.sh`
- Просмотр логов: `cat /opt/var/log/keensnap.log` или журнале KeeneticOS. Они сохраняются в каждом созданном архиве.

# Автоустановка

```shell
opkg update && opkg install curl ca-certificates wget-ssl && curl -fsSL https://raw.githubusercontent.com/spatiumstas/keensnap/main/install.sh | sh
```

### Ручная установка

1. Установите необходимые зависимости
   ```
   opkg update && opkg install ca-certificates wget-ssl && opkg remove wget-nossl
   ```
2. Установите opkg-репозиторий в систему
   ```
   mkdir -p /opt/etc/opkg
   echo "src/gz KeenSnap https://spatiumstas.github.io/KeenSnap/all" > /opt/etc/opkg/keensnap.conf
   ```

3. Установите пакет
   ```
   opkg update && opkg install keensnap
   ```  

# Настройка
1. Иметь настроенное расписание, созданное через веб-интерфейс [KeeneticOS](https://support.keenetic.ru/giga/kn-1010/ru/22348-disabling-all-leds-on-schedule.html). Вешать его на что-либо необязательно.
2. После запуска скрипта зайти в `Параметры` -> `Расписание и накопитель`.
3. В `Параметры` выбрать `Способ отправки`, затем отдельно заполнить блок `Telegram` или `Google Drive`.
4. В `Параметры` -> `Состав бэкапа` и `Автоудаление и обновление` включить нужные флаги.

<details>
  <summary>Подключение Telegram</summary>

1. Получить и скопировать `ID` своего аккаунта или чата через [UserInfoBot](https://t.me/userinfobot)
2. Создать своего бота через [BotFather](https://t.me/BotFather), скопировать его `token` и вставить в сервис

<img src="https://github.com/user-attachments/assets/ca5c31af-b29c-4d5a-b2d9-75ff64ba2c34" alt="" width="700">

</details>
<details>
  <summary>Подключение Google Drive</summary>

1. [Создать проект](https://console.cloud.google.com/projectcreate)
2. [Включить приложение Google Drive](https://console.cloud.google.com/apis/library/drive.googleapis.com)
3. [Создать приложение](https://console.cloud.google.com/auth/overview/create )
4. В [credentials](https://console.cloud.google.com/apis/credentials) создать `API Keys` с `Google Drive API` restrictions
5. Создать `OAuth client ID`. `Application type` -> `Web application`, `Authorized redirect URIs` -> `https://developers.google.com/oauthplayground`. Полученные Client ID и Client secret сохраняем
6. В [Playground](https://developers.google.com/oauthplayground) вписываем данные и URL `https://www.googleapis.com/auth/drive.file`. Выбираем `Authorize APIs`
<img width="1018" height="1274" alt="Screenshot_2" src="https://github.com/user-attachments/assets/dee36c9c-4338-414c-bcbc-4457d2dab643" />

7. Нажимаем `Exchange authorization code for tokens`.
8. Полученный `Refresh token`, `Client ID` и `Client secret` вставляем в сервис
<img width="490" height="643" alt="Screenshot_3" src="https://github.com/user-attachments/assets/aa705253-ecf6-49ef-be78-1b07e643aecf" />
</details>

##  Удаление

#### Пакета
```
opkg remove keensnap
```
#### Репозитория
```
rm /opt/etc/opkg/keensnap.conf
```