# Сводка по стенду ГИС «АУО» (вариант 3)

Стенд: Docker Compose, проект `gis`, 13 контейнеров на Debian 13 (trixie), 4 docker-сети. Всё ПО открытое. Состояние на 30.10.2026: `check-all.sh` после чистого прогона даёт 47 PASS из 47 (`results/06-checks.txt`), демонстрация `demo.sh` пройдена целиком (`results/06-demo-run.txt`).

## 1. Топология и фактический IP-план

Сети docker (все со статическими адресами, без `internal: true`, причина в разделе 9, п. 1):

| Сеть | Подсеть | Назначение |
|---|---|---|
| `gis_ext` | 198.51.100.0/24 | «Интернет» |
| `gis_transit` | 192.168.50.0/24 | общий коммутатор между МЭ, шлюзом ДМЗ, VPN, RADIUS |
| `gis_dmz` | 192.168.100.0/24 | ДМЗ |
| `gis_intra` | 192.168.200.0/24 | внутренняя сеть |
| wg0 (не docker-сеть) | 10.8.0.0/24 | туннель WireGuard, сервер 10.8.0.1, клиент 10.8.0.2 |

Узлы (адреса сняты командой `docker inspect`, см. шаг 1 в `results/06-demo-run.txt`):

| Узел | Адреса | Роль |
|---|---|---|
| fw-ext | ext 198.51.100.1, transit 192.168.50.1 | внешний МЭ, DNAT на web и vpn, masquerade для fw-int |
| gw-dmz | transit 192.168.50.2, dmz 192.168.100.1 | шлюз ДМЗ: МЭ + Suricata |
| vpn | transit 192.168.50.3, wg0 10.8.0.1 | сервер WireGuard |
| fw-int | transit 192.168.50.4, intra 192.168.200.1 | внутренний МЭ, Squid, RADIUS-клиент |
| radius | transit 192.168.50.5 | FreeRADIUS |
| web | dmz 192.168.100.10 | Apache + PHP, сайт Счётной палаты (учебный) |
| ftp | dmz 192.168.100.11 | vsftpd, копии и бэкапы |
| db | intra 192.168.200.10 | PostgreSQL |
| dc | intra 192.168.200.20 | Samba AD DC, домен gis.local |
| arm1 | intra 192.168.200.31 | АРМ, Debian-клиент домена |
| client | ext 198.51.100.10, wg0 10.8.0.2 | легитимный удалённый пользователь |
| attacker | ext 198.51.100.66 | внешний нарушитель |
| inet | ext 198.51.100.80 | «сайт в интернете» (`python3 -m http.server`) |

Публичный адрес сайта: 198.51.100.1 (tcp 80, 443), VPN: 198.51.100.1 udp 51820.

## 2. Узлы: образ, ПО, версии

Все образы собираются из общего `gis-base` (`debian:13`, iproute2, nftables, iputils-ping, curl, tcpdump, netcat-openbsd, dnsutils, procps). Версии сняты `dpkg -l` внутри контейнеров 30.10.2026.

| Узел | Образ | Ключевое ПО и версии | Назначение |
|---|---|---|---|
| fw-ext | gis-fw-ext | nftables 1.1.3 | фильтрация и DNAT на границе |
| gw-dmz | gis-gw-dmz | nftables 1.1.3, Suricata 7.0.10 (af-packet на transit и dmz) | МЭ ДМЗ и IDS |
| vpn | gis-vpn | wireguard-tools 1.0.20210914, nftables 1.1.3 | сервер защищённого канала |
| fw-int | gis-fw-int | nftables 1.1.3, Squid 6.13, freeradius-utils 3.2.7 (radtest) | внутренний МЭ, прокси с авторизацией |
| radius | gis-radius | FreeRADIUS 3.2.7 | аутентификация выхода в интернет |
| web | gis-web | Apache 2.4.69, PHP 8.4.27 (php8.4-pgsql), OpenSSL 3.5.7 | сайт, HTTPS на самоподписанном сертификате |
| ftp | gis-ftp | vsftpd 3.0.5 | хранилище бэкапов |
| db | gis-db | PostgreSQL 17.11 | база `site` |
| dc | gis-dc | Samba 4.22.11 (AD DC), krb5-user 1.21.3 | домен gis.local |
| arm1 | gis-arm1 | sssd-ad 2.10.1, adcli 0.9.2, AIDE 0.19.1, ClamAV 1.4.3, OpenSSH 10.0p1, libpam-pwquality 1.4.5, acl 2.3.2 | АРМ и аналоги Secret Net |
| client | gis-client | wireguard-tools, OpenSSH 10.0p1, sshpass 1.10, Chromium 156 (для скриншотов) | удалённый пользователь |
| attacker | gis-attacker | nmap 7.95, curl 8.14.1 | внешний нарушитель |
| inet | gis-inet | Python 3 (`http.server`) | цель для проверки выхода через Squid |

## 3. Замены относительно схемы

| В схеме | У нас | Причина |
|---|---|---|
| Astra Linux Orel | Debian 13 | свободный дистрибутив, решение группы, нет лицензии |
| pfSense | Debian + nftables + Squid | открытое ПО, режимы `protect`/`audit` переключаются скриптом, Squid даёт прокси с авторизацией |
| OpenVPN | WireGuard | решение группы, настраивается проще и работает в контейнере |
| Windows Server (DC) | Samba AD DC | открытая замена: Kerberos, LDAP, DNS, групповые политики паролей |
| Windows 10 (АРМ) | Debian-клиент (sssd, adcli) | без Windows и платного софта |
| Secret Net | ACL, AIDE, ClamAV, faillock/pwquality, журналы | Secret Net платный и под Windows; аналоги закрывают разграничение доступа, контроль целостности, антивирус, парольную политику, аудит (раздел 8, вопрос 6, и `results/05-domain-arm-radius.md`) |
| Snort | Suricata | решение группы, правила совместимы по синтаксису |
| ГОСТ-криптография | обычный TLS (самоподписанный сертификат) и WireGuard | сертифицированных ГОСТ-средств в открытом виде нет, на стенде это не моделировали |

## 4. Матрица проверок

Идентификаторы совпадают с `results/06-checks.txt` (`check-all.sh`). Результат везде PASS. Скрины лежат в `results/screens/` (рядом с каждым `.png` есть `.txt` с реальным выводом).

| Механизм | Проверка | ID | Скрин |
|---|---|---|---|
| МЭ | ping attacker → web в ДМЗ не проходит | 01.1 | 01-ping-attacker-dmz |
| МЭ | ping attacker → db во внутренней сети не проходит | 01.2 | 01-ping-attacker-intra |
| МЭ, DNAT | сайт открывается снаружи по 198.51.100.1 | 01.3 | 01-curl-client-web |
| МЭ | ssh на публичный адрес закрыт | 01.4 | 01-nmap-public-closed |
| МЭ | прямой доступ в ДМЗ в обход DNAT закрыт | 01.5 | 01-nmap-dmz-direct |
| МЭ | web → db:5432 разрешён, web → db:22 нет, ftp → db:5432 нет | 01.6–01.8 | 01-nc-web-db-5432, 01-nc-web-db-22, 01-nc-ftp-db |
| Маршрутизация | маршруты между зонами на роутерах | 01.9 | 01-routes-all |
| Режимы | audit пропускает, protect закрывает | 01.10, 01.11 | 01-mode-before-after, 01-audit-ping-attacker-intra |
| Правила МЭ | полные наборы nft | — | 01-nft-fwext, 01-nft-gwdmz, 01-nft-fwint |
| Web | http → 301 на https, https 200 | 02.1, 02.2 | 02-curl-http-redirect, 02-curl-https-headers, 02-site-https |
| Web | search.php отражает `<script>` (учебная XSS) | 02.3 | 02-xss-search-reflect |
| FTP | анонимный доступ запрещён | 02.4 | 02-ftp-anon-denied |
| FTP, БД | бэкап pg_dump → ftp | 02.5 | 02-backup-upload, 02-ftp-list-after-backup |
| БД | webapp: SELECT разрешён, internal_notes и ALTER запрещены | 02.6, 02.7 | 02-webapp-select-ok, 02-webapp-permission-denied |
| БД | pg_hba.conf отклоняет webapp с чужого адреса при выключенном МЭ | 02.8 | 02-pg-hba-reject |
| IDS | алерт XSS (sid 1000004) | 03.1 | 03-xss-curl, 03-xss-fastlog, 03-xss-evejson, 03-xss-browser |
| IDS | алерты SQLi (1000005, 1000006) | 03.2, 03.3 | 03-sqli-curl, 03-sqli-fastlog, 03-sqli-evejson |
| IDS | успешное HTTPS-подключение (1000003) | 03.4 | 03-https-curl, 03-https-fastlog, 03-https-evejson |
| IDS | FTP USER/PASS (1000008, 1000009) | 03.5 | 03-ftp-backup, 03-ftp-fastlog, 03-ftp-evejson |
| IDS | ICMP снаружи (1000001, режим audit) | 03.6 | 03-icmp-ping, 03-icmp-fastlog, 03-icmp-evejson |
| IDS | сканирование портов (1000007, режим audit) | 03.7 | 03-scan-nmap, 03-scan-fastlog, 03-scan-evejson |
| VPN | до туннеля arm1:22 недоступен | 04.1 | 04-before-tunnel |
| VPN | после туннеля arm1:22 доступен | 04.2 | 04-after-tunnel-arm |
| VPN | через туннель db и dc закрыты | 04.3 | 04-after-tunnel-denied |
| VPN | handshake на клиенте и сервере | 04.4, 04.5 | 04-wg-show-client, 04-wg-show-vpn |
| VPN | снаружи только udp/51820, внутри трафик расшифрован | — | 04-tcpdump-vpn-udp, 04-tcpdump-fwint-plain |
| VPN | отключение туннеля убирает доступ | 04.6 | 04-tunnel-down |
| VPN | ключ-самозванец не получает handshake | 04.7 | 04-badkey-no-handshake |
| Домен | домен gis.local на Samba AD | 05.1 | 05-dc-domain-info, 05-dc-dns-srv |
| Домен | arm1 введён в домен | 05.2 | 05-arm1-join |
| Домен | вход доменным пользователем, билет Kerberos | 05.3 | 05-arm1-domain-login |
| Домен | вход только группам Admin и Workgroup | 05.4 | 05-arm1-access-filter |
| Домен | блокировка после 3 неверных паролей, вход после сброса | 05.5 | 05-arm1-faillock-lock, 05-arm1-faillock-reset |
| Домен | слабый пароль отклоняется политикой | 05.6 | 05-dc-weak-password, 05-dc-passwordsettings |
| RADIUS | Accept и Reject (неверный пароль, guest) | 05.7 | 05-radius-radtest, 05-radius-config |
| Squid | 407 без учётки и с неверной, 200 с верной | 05.8 | 05-squid-auth |
| Squid, МЭ | прямой выход в интернет в обход Squid закрыт | 05.9 | 05-squid-direct, 05-fwint-input |
| Аналог Secret Net | ACL на /srv/archive | 05.10 | 05-acl |
| Аналог Secret Net | AIDE замечает изменение файла | 05.11 | 05-aide-ok, 05-aide-detect |
| Аналог Secret Net | ClamAV находит EICAR | 05.12 | 05-clamav-eicar |
| VPN + домен | вход доменным пользователем через туннель | 05.13 | 05-vpn-domain-ssh |
| Журналы | Squid, RADIUS, sshd, Apache, vsftpd | 05.14 | 05-logs-examples, 05-squid-log, 05-radius-log, 05-arm1-authlog |

Скрины, которые пересняли на этапе 06 из-за правок после своих этапов: `01-nft-fwint`, `04-nft-fwint-counters` (на fw-int в этапе 05 появилась цепочка input), `02-site-https`, `03-xss-browser` (веб-скрины, у них не было `.txt`). Подробности в `results/06-verify-demo.md`.

## 5. Учебные пароли и учётки стенда

Пароли учебные. Значения лежат в `stand/secrets/stand.env` (в `.gitignore`, в git не попадают), файл создаёт `up.sh` при первом запуске. Если файл есть, но в нём не хватает переменной, `up.sh` допишет только недостающие.

| Переменная | Значение | Где используется |
|---|---|---|
| `WEBAPP_DB_PASSWORD` | `Webapp2026stand` | роль PostgreSQL `webapp` (узел db), подключение из web |
| `FTP_BACKUP_PASSWORD` | `Backup2026stand` | пользователь vsftpd `ftpbackup`, `backup.sh` на db |
| `ARM_SSH_PASSWORD` | `Arm2026stand` | локальный пользователь `armuser` на arm1 (проверка VPN с этапа 04) |
| `DC_ADMIN_PASSWORD` | `DcAdmin2026stand` | `Administrator` домена gis.local, ввод arm1 в домен |
| `DOMAIN_USER_PASSWORD` | `Domain2026stand` | доменные пользователи `sysadmin`, `secadmin`, `archhead`, `archstaff1` |
| `RADIUS_SECRET` | `Radius2026stand` | общий секрет RADIUS между fw-int и radius |
| `PROXY_USER_PASSWORD` | `Proxy2026stand` | учётки FreeRADIUS для выхода через Squid |

Пользователи домена и группы:

| Пользователь | Группа | Вход на arm1 | Выход в интернет через Squid | Запись в /srv/archive |
|---|---|---|---|---|
| sysadmin, secadmin | Admin | да | да | нет (ACL только для Workgroup) |
| archhead, archstaff1 | Workgroup | да | да | да |
| guest (только в RADIUS) | Guest | нет | нет (явный Reject) | нет |
| Administrator | встроенная | нет (не входит в Admin/Workgroup) | нет | нет |

Ключи WireGuard лежат в `stand/secrets/wg/`, генерируются при первом старте контейнера `vpn`, не в git. Пароли без символов `#@/:%`: `FTP_BACKUP_PASSWORD` подставляется в `ftp://` URL. Доменные пароли проходят политику Samba (заглавные, строчные, цифры, длина от 10).

## 6. Как поднять, остановить, переключать режимы

Команды запускать из папки `gis/` (в fish работают как есть):

```
cd stand
scripts/up.sh            # сборка образов и запуск с нуля, создаёт secrets/stand.env при отсутствии
scripts/check-all.sh     # 47 проверок, таблица в results/06-checks.txt, код возврата 1 при FAIL
scripts/demo.sh          # демонстрация с паузами по Enter
scripts/mode.sh audit    # ACL выключены (all forward accept), IDS, DNAT, логи работают
scripts/mode.sh protect  # режим по умолчанию
scripts/down.sh          # docker compose down -v, только проект gis (тома домена удаляются)
scripts/shot.sh <имя> <команда>     # скрин терминала в results/screens
scripts/shot-web.sh <имя> <url>     # скрин страницы из client
```

Поднятие с нуля измерено 30.10.2026: `down -v` 12 с, `up.sh` 4 с (образы были в кэше docker, сборку без кэша не мерили), `check-all.sh` 92 с вместе с ожиданием готовности домена. Домен провизируется и arm1 входит в него автоматически, ручных шагов нет. Туннель WireGuard на client сам не поднимается: `docker exec gis-client wg-quick up wg0` и `down`.

## 7. Известные ограничения

- IPS не настраивали: Suricata работает как IDS (пассивно), сборка с поддержкой NFQ есть, правила nftables queue не сделаны (`results/03-ids.md`).
- Пассивный IDS не видит содержимое HTTPS (TLS 1.3), поэтому XSS и SQLi проверяли по `http://`.
- auditd в контейнере не запускается (нужен CAP_AUDIT_CONTROL, `--privileged` не использовали). Аудит заменён журналами sshd, Samba (`auth_audit`) и Squid.
- ClamAV работает с локальной сигнатурой EICAR, официальную базу не качали: сети стенда изолированы от интернета.
- GPO на arm1 не применяются (`ad_gpo_access_control = permissive`), двухфакторную аутентификацию (ключ + пароль) не моделировали, GUI АРМ нет.
- RADIUS проверяет пароли по своему файлу `users`, а не через ntlm_auth к Samba. Для fw-int выключен `require_message_authenticator`, потому что хелпер Squid не шлёт этот атрибут.
- Сертификат web самоподписанный. ГОСТ-криптографии нет.
- Журналы Squid и FreeRADIUS лежат внутри контейнеров и пропадают при `down -v`; журнал Suricata вынесен на хост в `stand/logs/gw-dmz/` (не в git).
- vsftpd 3.0.5 в контейнере изредка падает с SIGSEGV (код 139), причина не установлена. Запуск обёрнут перезапуском за 1 с, падения пишутся в `/var/log/vsftpd/restarts.log` на ftp (`results/06-verify-demo.md`, «Проблемы»).
- ICMP к самому fw-ext из ext отвечает (запрещён только транзит ICMP внутрь), поэтому «ping снаружи не проходит» показываем на адреса в ДМЗ и intra.
- Сети стенда без `internal: true` (раздел 9, п. 1): изоляция от интернета обеспечивается тем, что masquerade в docker выключен.

## 8. Вероятные вопросы на защите

1. **Зачем DNAT на fw-ext?** Внутренние адреса ДМЗ наружу не маршрутизируются, публичный адрес один (198.51.100.1). fw-ext переписывает tcp 80/443 на web (192.168.100.10) и udp 51820 на vpn (192.168.50.3). В forward правила помечены `ct status dnat`: без этого запрос прямо на 192.168.100.10 в обход публичного адреса тоже пропускался бы (проверка 01.5, `results/01-network-fw.md`, отступление 2).
2. **Зачем два режима `protect` и `audit`?** В примечаниях схемы сказано, что ACL на МЭ можно не настраивать для внешнего аудита. В `audit` forward accept, но маршрутизация, DNAT, Suricata и журналы работают. Переключает `mode.sh` загрузкой другого файла nft без перезапуска контейнеров. Видно на проверках 01.10 и 01.11: ping attacker → db в audit проходит, в protect нет.
3. **Чем IDS отличается от IPS?** IDS смотрит копию трафика и пишет алерты, не блокирует. IPS стоит в разрыве (nftables queue + NFQUEUE) и может дропать пакеты. У нас Suricata в режиме IDS (af-packet на transit и dmz), блокирует только nftables по статической политике.
4. **Что видно в логах при XSS?** В `fast.log` строка с `[1:1000004:1] Vozmozhnaya XSS-ataka: <script> v HTTP-zaprose` и адресами `198.51.100.66:порт -> 192.168.100.10:80`, по две строки на запрос (Suricata слушает два интерфейса). В `eve.json` тот же алерт в JSON. Запрос идёт по http://: по HTTPS содержимое зашифровано (TLS 1.3), пассивный IDS его не видит.
5. **Почему web не может ходить в db по ssh?** Три рубежа. На gw-dmz forward из dmz в intra разрешён только `192.168.100.10 → 192.168.200.10 tcp 5432` (счётчик `c_dmz_web_to_db`), остальное в `c_dmz_fwd_drop`. На fw-int то же правило (`c_int_web_to_db`). На самой db `pg_hba.conf` пускает роль webapp только с адреса web. Проверки 01.6, 01.7, 02.8.
6. **Чем заменили Secret Net?** По функциям: разграничение доступа к файлам, POSIX ACL на `/srv/archive` для группы Workgroup; контроль целостности, AIDE (ловит правку `sshd_config`); антивирус, ClamAV (находит EICAR); парольная политика и блокировка, pwquality и faillock плюс политика домена; аудит, журналы sshd, Samba `auth_audit`, Squid, RADIUS. auditd в контейнере не запустился.
7. **Почему VPN-клиент попадает только на arm1:22?** На fw-int единственное правило для 10.8.0.0/24: `→ 192.168.200.31 tcp 22` (счётчик `c_int_vpn_to_arm`). NAT на vpn не делали, поэтому на arm1 виден настоящий адрес 10.8.0.2 (проверка 05.13). db:5432 и dc:445 через туннель закрыты (04.3).
8. **Как реализован выход АРМ в интернет только после авторизации?** Прямой выход из intra наружу режет fw-int (`c_int_fwd_drop`, проверка 05.9). Разрешён только Squid fw-int:3128: без учётки или с неверной ответ 407, с верной 200. Squid проверяет пару логин/пароль через `basic_radius_auth` на radius (fw-int единственный клиент RADIUS). guest в RADIUS явно Reject.
9. **Чем Samba AD отличается от Windows DC и что у вас есть из домена?** Это открытая реализация AD: Kerberos, LDAP, встроенный DNS, группы Admin и Workgroup, политика паролей (сложность, длина 10, история 5, 90 дней, блокировка после 5 попыток на 15 минут). arm1 введён через `adcli join`, вход доменных пользователей идёт через SSSD, доступ ограничен `ad_access_filter` на группы Admin и Workgroup (Administrator не пускает). GPO не применяются.
10. **Почему сети не `internal: true`, как в задании?** Docker для internal-сетей ставит на хосте правило в `DOCKER-ISOLATION-STAGE-1`, которое блокирует пересылку пакета с «чужим» адресом назначения, даже через наш контейнер-роутер: между зонами было 100% потерь. Хост не трогали, вместо этого на каждой сети отключили masquerade (`enable_ip_masquerade: "false"`), так что наружу сети стенда не выходят (`results/01-network-fw.md`, отступление 1).

## 9. Отступления от схемы (кратко)

Полный список с причинами в `PROGRESS.md`, раздел «Отступления от схемы», и в `results/NN-*.md`.

1. Сети без `internal: true`, но с отключённым masquerade (этап 01).
2. `ct status dnat` в forward на fw-ext (этап 01).
3. Пассивные порты FTP 21100–21110, пользователь `ftpbackup` вместо `backup` (этап 02).
4. IDS без режима IPS, правила XSS и SQLi проверяются по `http://` (этап 03).
5. arm1: UID из SID, GPO не применяются, двухфакторку не моделировали (этап 05, часть А).
6. RADIUS по файлу users, ClamAV с локальной сигнатурой, auditd не запускается, GUI АРМ нет (этап 05, часть Б).
7. vsftpd запускается под перезапускающим супервизором из-за редкого SIGSEGV (этап 06).
