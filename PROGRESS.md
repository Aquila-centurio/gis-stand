# PROGRESS — журнал работы над стендом ГИС

Сдача проекта: суббота 7 ноября 2026, 00:00. Ориентир: стенд готов к 3 ноября, на отчёт остаётся запас.

## Этапы
- [x] 01 — сети, роутеры, межсетевые экраны (`prompts/01-network-fw.md`)
- [x] 02 — сервисы ДМЗ и БД: web, FTP, PostgreSQL (`prompts/02-dmz-services.md`)
- [ ] 03 — IDS/IPS на шлюзе ДМЗ (`prompts/03-ids.md`)
- [ ] 04 — VPN WireGuard и удалённый доступ (`prompts/04-vpn.md`)
- [ ] 05 — домен, АРМ, RADIUS+Squid, аналоги Secret Net (`prompts/05-domain-arm-radius.md`)
- [ ] 06 — итоговые проверки, сводка, демо для защиты (`prompts/06-verify-demo.md`)

## Текущее состояние
(Что сейчас работает, что нет, как поднять стенд. Обновляй, а не дописывай в конец.)

Этапы 01-02 готовы. `cd stand && scripts/up.sh` поднимает с нуля: 4 сети (`gis_ext`, `gis_transit`, `gis_dmz`, `gis_intra`), 13 контейнеров; при первом запуске также создаёт `stand/secrets/stand.env` с учебными паролями (см. `results/00-summary.md`). Маршрутизация между всеми зонами работает через контейнеры-роутеры (fw-ext, gw-dmz, fw-int, vpn-заглушка). nftables с режимами `protect`/`audit` настроены на fw-ext, gw-dmz, fw-int — `scripts/mode.sh protect|audit` переключает без пересоздания контейнеров.

- **web** (dmz .10): Apache+PHP, учебный сайт «Интернет-сайт Счётной палаты РФ» (главная/новости/документы/поиск), HTTPS на самоподписанном сертификате (80 → редирект на 443). `search.php` намеренно уязвим к XSS (задел для этапа 03).
- **db** (intra .10): PostgreSQL 17, база `site` (news/documents/internal_notes), роль `webapp` только с SELECT на news/documents и только с адреса web (`pg_hba.conf`).
- **ftp** (dmz .11): vsftpd, пользователь `ftpbackup` (chroot, без анонимного доступа), пассивные порты 21100-21110. `backup.sh` на db — `pg_dump` → загрузка на ftp.
- dc, arm1, radius, vpn — пустые заглушки (сервисы появятся в следующих этапах).
- `scripts/shot-web.sh` — скриншот страницы из `client` headless-хромиумом.

Сейчас стенд в режиме `protect` (по умолчанию).

Все проверки из `prompts/01-network-fw.md` и `prompts/02-dmz-services.md` пройдены, детали и скрины — `results/01-network-fw.md`, `results/02-dmz-services.md`, `results/screens/01-*`, `results/screens/02-*`.

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

## Журнал (новые записи сверху)
Формат записи: `ДАТА ВРЕМЯ — этап NN — что сделано / что сломалось / что дальше`

2026-10-30 — этап 02 — web (Apache+PHP, HTTPS, учебная XSS в search.php), ftp (vsftpd, пользователь ftpbackup, бэкап pg_dump→ftp), db (PostgreSQL, роль webapp с минимальными правами, pg_hba ограничен адресом web) подняты вместо заглушек. Обновлены правила fw-int (db→ftp, пассивные порты для arm1→ftp). Нашли и исправили: конфликт имени `backup` с системной учёткой, отсутствующий `/var/run/vsftpd/empty`, `#` в пароле ломал FTP URL в curl. Проверили pg_hba как независимый от МЭ рубеж (временный audit-режим). Все проверки из `prompts/02-dmz-services.md` — PASS, результаты в `results/02-dmz-services.md`. Дальше: этап 03 (IDS/IPS на gw-dmz).

2026-10-30 — этап 01 — каркас стенда поднят: 4 сети, 13 узлов, маршрутизация, nftables (protect/audit) на 3 МЭ, скрипты up/down/mode/shot. Нашли и обошли блокировку форвардинга между docker internal-сетями (DOCKER-ISOLATION-STAGE-1) без правок хоста. Нашли и закрыли прямой доступ к dmz в обход DNAT (`ct status dnat`). Все проверки из `prompts/01-network-fw.md` — PASS, результаты в `results/01-network-fw.md`. Дальше: этап 02 (web/FTP/PostgreSQL).
