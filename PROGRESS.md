# PROGRESS — журнал работы над стендом ГИС

Сдача проекта: суббота 7 ноября 2026, 00:00. Ориентир: стенд готов к 3 ноября, на отчёт остаётся запас.

## Этапы
- [x] 01 — сети, роутеры, межсетевые экраны (`prompts/01-network-fw.md`)
- [x] 02 — сервисы ДМЗ и БД: web, FTP, PostgreSQL (`prompts/02-dmz-services.md`)
- [x] 03 — IDS/IPS на шлюзе ДМЗ (`prompts/03-ids.md`)
- [x] 04 — VPN WireGuard и удалённый доступ (`prompts/04-vpn.md`)
- [x] 05 — домен, АРМ, RADIUS+Squid, аналоги Secret Net (`prompts/05-domain-arm-radius.md`)
  - [x] часть А: dc (Samba AD), ввод arm1 в домен, доменный вход, faillock/pwquality
  - [x] часть Б: RADIUS, Squid на fw-int, inet, аналоги Secret Net (ACL, AIDE, ClamAV, аудит), таблица логов, вход через VPN доменным пользователем
- [x] 06 — итоговые проверки, сводка, демо для защиты (`prompts/06-verify-demo.md`)

## Текущее состояние
(Что сейчас работает, что нет, как поднять стенд. Обновляй, а не дописывай в конец.)

Все этапы 01-06 готовы. Стенд готов к сдаче, осталось оформление отчёта (делает пользователь). `cd stand && scripts/up.sh` поднимает с нуля: 4 сети (`gis_ext`, `gis_transit`, `gis_dmz`, `gis_intra`), 13 контейнеров, named volume `gis_dc-lib`/`gis_dc-etc` для базы домена; создаёт `stand/secrets/stand.env` с учебными паролями или дописывает в него недостающие переменные (см. `results/00-summary.md`). Проверено 30.10 полным `docker compose down -v` + `up.sh` (после части Б этапа 05): домен провизируется, arm1 входит в него сам, Squid+RADIUS, ACL, AIDE, вход через VPN работают без ручных действий. Маршрутизация между всеми зонами работает через контейнеры-роутеры (fw-ext, gw-dmz, fw-int, vpn-заглушка). nftables с режимами `protect`/`audit` настроены на fw-ext, gw-dmz, fw-int — `scripts/mode.sh protect|audit` переключает без пересоздания контейнеров.

- **web** (dmz .10): Apache+PHP, учебный сайт «Интернет-сайт Счётной палаты РФ» (главная/новости/документы/поиск), HTTPS на самоподписанном сертификате (80 → редирект на 443). `search.php` намеренно уязвим к XSS.
- **db** (intra .10): PostgreSQL 17, база `site` (news/documents/internal_notes), роль `webapp` только с SELECT на news/documents и только с адреса web (`pg_hba.conf`).
- **ftp** (dmz .11): vsftpd, пользователь `ftpbackup` (chroot, без анонимного доступа), пассивные порты 21100-21110. `backup.sh` на db — `pg_dump` → загрузка на ftp.
- **gw-dmz**: кроме МЭ (nftables, с этапа 01) теперь ещё Suricata 7.0.10 (IDS, af-packet на transit+dmz), 9 своих правил (`stand/nodes/gw-dmz/suricata/local.rules`): ICMP, успешное HTTPS-подключение, XSS, SQLi (2 варианта), сканирование портов, FTP-логин. Логи на хосте в `stand/logs/gw-dmz/` (`fast.log`, `eve.json`, не в git). IPS (nftables queue + NFQUEUE) не делали — не хватило времени, см. `results/03-ids.md`.
- **dc**: журнал аутентификации Samba `log level = 1 auth_audit:3` (entrypoint правит smb.conf при каждом старте).
- **dc** (intra .20): Samba 4.22 AD DC, домен `gis.local` (realm `GIS.LOCAL`, NetBIOS `GIS`),
  встроенный DNS. Провизия один раз при первом старте (база в volume), группы Admin (sysadmin,
  secadmin) и Workgroup (archhead, archstaff1) и парольная политика (сложность, длина 10, история 5,
  90 дней, блокировка после 5 попыток на 15 мин) применяются при каждом старте. NT ACL в xattr
  `user.NTACL` (без CAP_SYS_ADMIN).
- **radius** (transit .5): FreeRADIUS 3.2.7, клиент только fw-int (секрет `RADIUS_SECRET`),
  пользователи в `mods-config/files/authorize` (archstaff1, archhead, sysadmin, secadmin с паролем
  `PROXY_USER_PASSWORD`, guest — явный Reject). Для fw-int `require_message_authenticator = no`
  (хелпер Squid не шлёт атрибут). Лог `/var/log/freeradius/radius.log` (внутри контейнера).
- **fw-int**: Squid 6.13 на 192.168.200.1:3128, Basic-авторизация через `basic_radius_auth` →
  radius. Новая цепочка input (protect): к самому fw-int только 3128 из intra и ICMP. Лог
  `/var/log/squid/access.log` (внутри контейнера). `max_filedescriptors 4096` обязателен (иначе падает в Docker).
- **arm1** (часть Б): `/srv/archive` с ACL только для workgroup, AIDE (`/etc/aide/aide-gis.conf`,
  база при старте), ClamAV с локальной сигнатурой EICAR, rsyslog → `/var/log/auth.log` (sshd
  теперь пишет туда, а не в `docker logs`). auditd в контейнере не работает (нужен CAP_AUDIT_CONTROL).
- **client**: добавлен sshpass и env_file, вход через VPN доменным пользователем работает.
- `scripts/shot-web.sh` — скриншот страницы из `client` headless-хромиумом.
- **vpn** (transit .3): WireGuard-сервер wg0 (10.8.0.1/24, udp 51820), ключи в `stand/secrets/wg/`
  (генерируются автоматически при первом старте контейнера, не в git). Свой nftables: принимает
  только udp/51820 и established/related, ssh/icmp к самому vpn закрыты; forward — accept (NAT
  нет, чтобы на fw-int был виден настоящий адрес клиента 10.8.0.x).
- **client** (ext .10, в туннеле 10.8.0.2/32): конфиги WireGuard готовятся сразу при старте
  (`wg0.conf` — рабочий, `wg0-badkey.conf` — незарегистрированный ключ), но интерфейс не
  поднимается автоматически — `wg-quick up/down wg0` делается вручную для проверки до/после.
- **arm1** (intra .31): клиент домена (DNS на dc, `adcli join` при старте, если в keytab нет
  ARM1$; SSSD id/auth/access_provider=ad, UID из SID). Входить могут только группы Admin и
  Workgroup (`ad_access_filter`). PAM: faillock (3 попытки/15 мин → блок 5 мин), pwquality,
  mkhomedir. sshd для доменных и локального `armuser` (пароль `ARM_SSH_PASSWORD`, нужен этапу 04).
  Тестовый вход: `docker exec gis-arm1 bash -c 'sshpass -p "$DOMAIN_USER_PASSWORD" ssh archstaff1@localhost'`.
- Правило `fw-int` на VPN-клиентов и DNAT на `fw-ext` для udp/51820 были готовы ещё с этапа 01,
  на этапе 04 только проверены.

- **Этап 06**: `scripts/check-all.sh` — 48 проверок этапов 01-05, таблица в `results/06-checks.txt`, код возврата 1 при FAIL (сам ждёт готовности домена, возвращает `protect` и гасит туннели при выходе). После чистого `down -v` + `up.sh`: 48 PASS (down 13 с, up 4 с с кэшем образов, check-all 115 с). `scripts/demo.sh` — демонстрация с паузами по Enter, сухой прогон `yes '' | scripts/demo.sh`, вывод в `results/06-demo-run.txt`. Сводка для отчёта — `results/00-summary.md`, результаты этапа — `results/06-verify-demo.md`.
- **ftp**: `init: true` в compose — PID 1 это `docker-init`, vsftpd его дочерний процесс (в роли PID 1 vsftpd падал с кодом 139 от SIGCHLD осиротевшего процесса, см. «Известные проблемы»).

Сейчас стенд в режиме `protect` (по умолчанию).

Важно для этапа 04+: web отдаёт TLS 1.3 по умолчанию — Suricata (как и любой пассивный сетевой IDS)
не видит полезную нагрузку HTTPS-запросов, только метаданные TLS-сессии. Для проверок, которым нужна
видимость запроса (payload-based правила), использовать `http://` (порт 80, запрос виден в открытом
виде ещё до редиректа), а не `https://`. Подробности — `results/03-ids.md`, «Отступления», п.1-2.

Все проверки из `prompts/01-network-fw.md`, `prompts/02-dmz-services.md`, `prompts/03-ids.md`, `prompts/04-vpn.md` пройдены, детали и скрины — `results/01-network-fw.md`, `results/02-dmz-services.md`, `results/03-ids.md`, `results/04-vpn.md`, `results/screens/01-*` … `results/screens/04-*`. Проверки части А этапа 05 (dc и arm1) — `results/05-domain-arm-radius.md`, `results/screens/05-*`.

## Известные проблемы и обходы
- Docker для сетей с `internal: true` сам ставит на хосте (в `DOCKER-ISOLATION-STAGE-1`, не трогая `/etc/nftables.conf`) правило, блокирующее пересылку пакета с чужим для данного bridge адресом назначения — даже если сосед по bridge является нашим контейнером-роутером. Из-за этого обошлись без `internal: true` (см. «Отступления»). Если при `docker compose up` на новой машине снова появится 100% потерь между зонами при живых маршрутах и ARP — проверить `docker network inspect gis_<сеть> --format '{{.Internal}}'`, должно быть `false`.
- `sudo` внутри Claude Code не может запросить пароль (нет tty) — диагностические/host-level команды, если понадобятся, выполнять в обычном терминале руками.
- Сети стенда изолированы от реального интернета (по задумке этапа 01): `docker exec apt-get install` в уже запущенный контейнер не работает. Пакеты добавлять только в Dockerfile (сборка идёт на хосте с обычной сетью).
- На arm1 `chpasswd` идёт через PAM и pwquality: новые пароли локальных учёток должны проходить политику (заглавные, строчные, цифры, длина от 10, без имени пользователя), иначе entrypoint не задаст пароль.
- UID доменных пользователей на arm1 вычисляются из SID и меняются после `down -v` (новая провизия = новый SID). Не завязываться на конкретные UID в скриптах.
- vsftpd нельзя запускать PID 1 контейнера: завершение любого осиротевшего процесса в контейнере (например, фонового процесса из `docker exec`) роняет его с SIGSEGV (код 139). Воспроизведение: `docker exec gis-ftp sh -c 'sleep 1 & exit 0'`. Поэтому у ftp `init: true`; проверка 02.9 в `check-all.sh` следит за этим. `seccomp_sandbox=NO` тут ни при чём. Разбор — `results/02-dmz-services.md`, «Проблемы», п. 5.
- Suricata иногда пишет алерт в `fast.log` с задержкой в несколько секунд: в проверках опрашивать файл до 20 с, а не ждать фиксированное время.
- Имя пользователя `backup` занято системной учёткой Debian (uid 34, `/var/backups`) — для FTP-учёток использовать другие имена (сейчас `ftpbackup`).

## Отступления от схемы
1. Сети `gis_ext/transit/dmz/intra` подняты **без** `internal: true`; вместо этого на каждой сети `driver_opts: com.docker.network.bridge.enable_ip_masquerade: "false"`. Причина и проверка — `results/01-network-fw.md`, раздел «Отступления от схемы и причины», п.1. Хост не менялся, только `stand/docker-compose.yml`.
2. На fw-ext DNAT-правила форварда дополнены `ct status dnat` — иначе прямой запрос на внутренний IP dmz в обход публичного адреса тоже форвардился бы. Детали — `results/01-network-fw.md`, п.2.
3. Диапазон пассивных портов FTP зафиксирован как 21100-21110 в правиле gw-dmz, используется в `vsftpd` с этапа 02.
4. В `gis-base` добавлен пакет `iputils-tracepath` (в Debian 13 он отдельно от `iputils-ping`).
5. FTP-пользователь для бэкапов назван `ftpbackup` (не `backup` — занято системной учёткой). `seccomp_sandbox=NO` и `allow_writeable_chroot=YES` в vsftpd.conf. На `client` добавлен Chromium с `--no-sandbox` для `shot-web.sh`. Подробности и обоснование — `results/02-dmz-services.md`, «Отступления от схемы и причины».
6. Suricata на gw-dmz настроена своим минимальным `suricata.yaml` (не патч дистрибутивного). Правило
   «успешное HTTPS-подключение» не смотрит на сертификат сервера (TLS 1.3 его шифрует), XSS/SQLi
   проверяются через `http://`, не `https://` (payload HTTPS не виден пассивному IDS в принципе).
   IPS-режим не настраивали. Подробности — `results/03-ids.md`, «Отступления от схемы и причины».

7. dc: NT ACL в xattr `user.NTACL` вместо `security.NTACL` (без CAP_SYS_ADMIN). arm1: UID из SID
   (RFC2307-атрибуты не заполняли), GPO не применяются (`ad_gpo_access_control = permissive`),
   `pam_loginuid` в sshd переведён в optional (нет CAP_AUDIT_CONTROL), двухфакторку (ключ+пароль)
   не моделировали. Подробности — `results/05-domain-arm-radius.md`, «Отступления».

8. Этап 05, часть Б: RADIUS по файлу users (без ntlm_auth к Samba), для fw-int выключен
   require_message_authenticator (Squid его не шлёт), ClamAV с локальной сигнатурой EICAR вместо
   официальной базы, auditd не запускается в контейнере, журналы Squid/FreeRADIUS внутри
   контейнеров, GUI АРМ не делали. Подробности — `results/05-domain-arm-radius.md`, «Отступления», п. 8-14.

9. ftp запускается с `init: true` (этап 06): vsftpd не может быть PID 1. Подробности — `results/02-dmz-services.md`, «Проблемы», п. 5.

## Журнал (новые записи сверху)
Формат записи: `ДАТА ВРЕМЯ — этап NN — что сделано / что сломалось / что дальше`

2026-10-30 — этап 06 — написаны `check-all.sh` (47 проверок), `demo.sh` (7 шагов), сводка `results/00-summary.md` и `results/06-verify-demo.md`. Чистый прогон `down -v` + `up.sh` + `check-all.sh`: 47 PASS, 108 с; `demo.sh` пройден целиком без правок. Нашли и исправили: инвертированный флаг в проверке faillock (05.5), ложный PASS проверки анонимного FTP (02.4, теперь требует ответ 530), фиксированный `sleep` для алертов Suricata (теперь опрос до 20 с), гонку после `up.sh` (`wait_ready`), пути с пробелами в demo. Нашли реальный дефект стенда: vsftpd как PID 1 падал с SIGSEGV (код 139) от SIGCHLD осиротевшего процесса; сначала поставили цикл-перезапуск, затем нашли причину (воспроизведение 3/3 через `sleep 1 &` в `docker exec`) и заменили на `init: true`, добавили проверку 02.9, чистый прогон 48/48. Пересняты скрины `01-nft-fwint`, `04-nft-fwint-counters` (устарели после этапа 05), `02-site-https`, `03-xss-browser` (к ним добавлены `.txt`). Секретов в `results/` нет. Дальше: оформление отчёта по `results/` и `docs/variant3.md`.

2026-10-30 — этап 05, часть Б — FreeRADIUS (клиент fw-int, users-файл, guest Reject), Squid на
fw-int с basic_radius_auth (407 без учётки/с неверной, 200 с верной, прямой выход закрыт), цепочка
input на fw-int (только 3128 из intra). arm1: ACL на /srv/archive для Workgroup, AIDE, ClamAV с
локальной сигнатурой EICAR, rsyslog → auth.log; auditd не работает без CAP_AUDIT_CONTROL (не давали).
dc: auth_audit в log.samba. client: вход через VPN доменным пользователем. Нашли и исправили: Squid
падал (nofile ~1e9 → max_filedescriptors 4096); FreeRADIUS в режиме auto после radtest начинал
требовать Message-Authenticator от fw-int и молча дропал запросы Squid (→ require_message_authenticator
= no для fw-int); default-ACL открывал файлы группе domain users (→ d:g::---). Проверки 12-24 PASS,
таблицы журналов и Secret Net в results/05. Проверено down -v + up.sh. GUI АРМ не делали. Дальше: этап 06.

2026-10-30 — этап 05, часть А — dc: Samba AD DC gis.local (провизия без CAP_SYS_ADMIN через
user.NTACL), группы Admin/Workgroup, 4 пользователя, парольная политика домена. arm1: adcli join +
SSSD, вход доменными пользователями по ssh с билетом Kerberos, доступ только Admin/Workgroup,
faillock (3 попытки), pwquality. Нашли и исправили: pam_unix в account пропускал любого
NSS-пользователя мимо ad_access_filter (Administrator входил на АРМ); нет словаря cracklib
ломал chpasswd. Проверено с нуля (down -v + up.sh), все 11 проверок PASS, скрины 05-dc-*,
05-arm1-*. Дальше: часть Б — RADIUS, Squid на fw-int, inet, ACL/AIDE/ClamAV/аудит, таблица
логов, вход через VPN доменным пользователем (на client нужно доставить openssh-client и sshpass).

2026-10-30 — этап 04 — WireGuard-сервер на vpn (wg0, 10.8.0.1/24, udp 51820), ключи
генерируются автоматически в stand/secrets/wg при первом запуске (не в git). На client готовятся
конфиги wg0.conf и wg0-badkey.conf, туннель поднимается вручную (wg-quick up/down) для проверки
до/после. На arm1 — заглушка с sshd (пользователь armuser) как цель для проверки политики
VPN-клиент → arm1:22 (правило на fw-int и DNAT на fw-ext были готовы ещё с этапа 01). На vpn
добавлен nftables: принимает только udp/51820, остальное к самому vpn закрыто, NAT не делали —
на fw-int виден настоящий адрес клиента в туннеле. Проверили: до туннеля доступа нет, после —
разрешён только arm1:22 (db:5432 и dc — нет), wg show показывает handshake/transfer без
приватных ключей, tcpdump подтвердил, что снаружи (vpn/transit) только UDP/51820, а внутри
(fw-int/intra) трафик уже расшифрован (виден SSH-банер в открытом виде), отключение туннеля
убирает доступ, клиент с незарегистрированным ключом (bad-client) не получает handshake.
Все обязательные проверки из prompts/04-vpn.md — PASS, результаты в results/04-vpn.md. Дальше:
этап 05 (домен, АРМ, RADIUS+Squid, аналоги Secret Net).

2026-10-30 — этап 03 — Suricata (IDS, af-packet на transit+dmz) поднята на gw-dmz, 9 своих правил
(ICMP, успешное HTTPS-подключение, XSS, 2×SQLi, сканирование портов, FTP-логин). Логи fast.log/eve.json
смонтированы на хост в stand/logs/gw-dmz (gitignore). Главная находка: web отдаёт TLS 1.3, пассивный
IDS не видит payload HTTPS-запросов (ни сертификат, ни HTTP-строку) — переписали правило успешного
подключения на flow:to_client (без контента), а XSS/SQLi проверяли через http:// вместо https://
(строка запроса видна в открытом виде ещё до TLS). ICMP и сканирование портов проверяли в режиме audit
(в protect трафик не доходит до gw-dmz в нужном объёме). IPS (nftables queue + NFQUEUE) не делали —
не хватило времени после диагностики TLS 1.3, задел для будущего остался (suricata собран с NFQ).
Все обязательные проверки из prompts/03-ids.md — PASS, результаты в results/03-ids.md. Дальше: этап 04
(VPN WireGuard).

2026-10-30 — этап 02 — web (Apache+PHP, HTTPS, учебная XSS в search.php), ftp (vsftpd, пользователь ftpbackup, бэкап pg_dump→ftp), db (PostgreSQL, роль webapp с минимальными правами, pg_hba ограничен адресом web) подняты вместо заглушек. Обновлены правила fw-int (db→ftp, пассивные порты для arm1→ftp). Нашли и исправили: конфликт имени `backup` с системной учёткой, отсутствующий `/var/run/vsftpd/empty`, `#` в пароле ломал FTP URL в curl. Проверили pg_hba как независимый от МЭ рубеж (временный audit-режим). Все проверки из `prompts/02-dmz-services.md` — PASS, результаты в `results/02-dmz-services.md`. Дальше: этап 03 (IDS/IPS на gw-dmz).

2026-10-30 — этап 01 — каркас стенда поднят: 4 сети, 13 узлов, маршрутизация, nftables (protect/audit) на 3 МЭ, скрипты up/down/mode/shot. Нашли и обошли блокировку форвардинга между docker internal-сетями (DOCKER-ISOLATION-STAGE-1) без правок хоста. Нашли и закрыли прямой доступ к dmz в обход DNAT (`ct status dnat`). Все проверки из `prompts/01-network-fw.md` — PASS, результаты в `results/01-network-fw.md`. Дальше: этап 02 (web/FTP/PostgreSQL).
