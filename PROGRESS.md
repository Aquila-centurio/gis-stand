# PROGRESS — журнал работы над стендом ГИС

Сдача проекта: суббота 7 ноября 2026, 00:00. Ориентир: стенд готов к 3 ноября, на отчёт остаётся запас.

## Этапы
- [x] 01 — сети, роутеры, межсетевые экраны (`prompts/01-network-fw.md`)
- [x] 02 — сервисы ДМЗ и БД: web, FTP, PostgreSQL (`prompts/02-dmz-services.md`)
- [x] 03 — IDS/IPS на шлюзе ДМЗ (`prompts/03-ids.md`)
- [x] 04 — VPN WireGuard и удалённый доступ (`prompts/04-vpn.md`)
- [ ] 05 — домен, АРМ, RADIUS+Squid, аналоги Secret Net (`prompts/05-domain-arm-radius.md`)
- [ ] 06 — итоговые проверки, сводка, демо для защиты (`prompts/06-verify-demo.md`)

## Текущее состояние
(Что сейчас работает, что нет, как поднять стенд. Обновляй, а не дописывай в конец.)

Этапы 01-03 готовы. `cd stand && scripts/up.sh` поднимает с нуля: 4 сети (`gis_ext`, `gis_transit`, `gis_dmz`, `gis_intra`), 13 контейнеров; при первом запуске также создаёт `stand/secrets/stand.env` с учебными паролями (см. `results/00-summary.md`). Маршрутизация между всеми зонами работает через контейнеры-роутеры (fw-ext, gw-dmz, fw-int, vpn-заглушка). nftables с режимами `protect`/`audit` настроены на fw-ext, gw-dmz, fw-int — `scripts/mode.sh protect|audit` переключает без пересоздания контейнеров.

- **web** (dmz .10): Apache+PHP, учебный сайт «Интернет-сайт Счётной палаты РФ» (главная/новости/документы/поиск), HTTPS на самоподписанном сертификате (80 → редирект на 443). `search.php` намеренно уязвим к XSS.
- **db** (intra .10): PostgreSQL 17, база `site` (news/documents/internal_notes), роль `webapp` только с SELECT на news/documents и только с адреса web (`pg_hba.conf`).
- **ftp** (dmz .11): vsftpd, пользователь `ftpbackup` (chroot, без анонимного доступа), пассивные порты 21100-21110. `backup.sh` на db — `pg_dump` → загрузка на ftp.
- **gw-dmz**: кроме МЭ (nftables, с этапа 01) теперь ещё Suricata 7.0.10 (IDS, af-packet на transit+dmz), 9 своих правил (`stand/nodes/gw-dmz/suricata/local.rules`): ICMP, успешное HTTPS-подключение, XSS, SQLi (2 варианта), сканирование портов, FTP-логин. Логи на хосте в `stand/logs/gw-dmz/` (`fast.log`, `eve.json`, не в git). IPS (nftables queue + NFQUEUE) не делали — не хватило времени, см. `results/03-ids.md`.
- dc, radius — пустые заглушки (сервисы появятся в этапе 05).
- `scripts/shot-web.sh` — скриншот страницы из `client` headless-хромиумом.
- **vpn** (transit .3): WireGuard-сервер wg0 (10.8.0.1/24, udp 51820), ключи в `stand/secrets/wg/`
  (генерируются автоматически при первом старте контейнера, не в git). Свой nftables: принимает
  только udp/51820 и established/related, ssh/icmp к самому vpn закрыты; forward — accept (NAT
  нет, чтобы на fw-int был виден настоящий адрес клиента 10.8.0.x).
- **client** (ext .10, в туннеле 10.8.0.2/32): конфиги WireGuard готовятся сразу при старте
  (`wg0.conf` — рабочий, `wg0-badkey.conf` — незарегистрированный ключ), но интерфейс не
  поднимается автоматически — `wg-quick up/down wg0` делается вручную для проверки до/после.
- **arm1** (intra .31): временная заглушка с sshd (openssh-server, пользователь `armuser`,
  пароль `ARM_SSH_PASSWORD`) — цель для проверки доступа VPN-клиента по политике
  (10.8.0.0/24 → arm1 tcp 22, остальное в intra и в dmz запрещено). Полноценный АРМ — этап 05.
- Правило `fw-int` на VPN-клиентов и DNAT на `fw-ext` для udp/51820 были готовы ещё с этапа 01,
  на этапе 04 только проверены.

Сейчас стенд в режиме `protect` (по умолчанию).

Важно для этапа 04+: web отдаёт TLS 1.3 по умолчанию — Suricata (как и любой пассивный сетевой IDS)
не видит полезную нагрузку HTTPS-запросов, только метаданные TLS-сессии. Для проверок, которым нужна
видимость запроса (payload-based правила), использовать `http://` (порт 80, запрос виден в открытом
виде ещё до редиректа), а не `https://`. Подробности — `results/03-ids.md`, «Отступления», п.1-2.

Все проверки из `prompts/01-network-fw.md`, `prompts/02-dmz-services.md`, `prompts/03-ids.md`, `prompts/04-vpn.md` пройдены, детали и скрины — `results/01-network-fw.md`, `results/02-dmz-services.md`, `results/03-ids.md`, `results/04-vpn.md`, `results/screens/01-*` … `results/screens/04-*`.

## Известные проблемы и обходы
- Docker для сетей с `internal: true` сам ставит на хосте (в `DOCKER-ISOLATION-STAGE-1`, не трогая `/etc/nftables.conf`) правило, блокирующее пересылку пакета с чужим для данного bridge адресом назначения — даже если сосед по bridge является нашим контейнером-роутером. Из-за этого обошлись без `internal: true` (см. «Отступления»). Если при `docker compose up` на новой машине снова появится 100% потерь между зонами при живых маршрутах и ARP — проверить `docker network inspect gis_<сеть> --format '{{.Internal}}'`, должно быть `false`.
- `sudo` внутри Claude Code не может запросить пароль (нет tty) — диагностические/host-level команды, если понадобятся, выполнять в обычном терминале руками.
- Сети стенда изолированы от реального интернета (по задумке этапа 01): `docker exec apt-get install` в уже запущенный контейнер не работает. Пакеты добавлять только в Dockerfile (сборка идёт на хосте с обычной сетью).
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

## Журнал (новые записи сверху)
Формат записи: `ДАТА ВРЕМЯ — этап NN — что сделано / что сломалось / что дальше`

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
