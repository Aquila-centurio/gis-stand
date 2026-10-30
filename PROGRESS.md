# PROGRESS — журнал работы над стендом ГИС

Сдача проекта: суббота 7 ноября 2026, 00:00. Ориентир: стенд готов к 3 ноября, на отчёт остаётся запас.

## Этапы
- [x] 01 — сети, роутеры, межсетевые экраны (`prompts/01-network-fw.md`)
- [ ] 02 — сервисы ДМЗ и БД: web, FTP, PostgreSQL (`prompts/02-dmz-services.md`)
- [ ] 03 — IDS/IPS на шлюзе ДМЗ (`prompts/03-ids.md`)
- [ ] 04 — VPN WireGuard и удалённый доступ (`prompts/04-vpn.md`)
- [ ] 05 — домен, АРМ, RADIUS+Squid, аналоги Secret Net (`prompts/05-domain-arm-radius.md`)
- [ ] 06 — итоговые проверки, сводка, демо для защиты (`prompts/06-verify-demo.md`)

## Текущее состояние
(Что сейчас работает, что нет, как поднять стенд. Обновляй, а не дописывай в конец.)

Этап 01 готов. `cd stand && scripts/up.sh` поднимает с нуля: 4 сети (`gis_ext`, `gis_transit`, `gis_dmz`, `gis_intra`), 13 контейнеров. Маршрутизация между всеми зонами работает через контейнеры-роутеры (fw-ext, gw-dmz, fw-int, vpn-заглушка). nftables с режимами `protect`/`audit` настроены на fw-ext, gw-dmz, fw-int — `scripts/mode.sh protect|audit` переключает без пересоздания контейнеров. web отдаёт статическую заглушку на 80 (`python3 -m http.server`), db слушает 5432/22 через `nc` для проверки МЭ. ftp, dc, arm1, radius, vpn — пустые заглушки (сервисы появятся в следующих этапах). Сейчас стенд в режиме `protect` (по умолчанию).

Все проверки из `prompts/01-network-fw.md` пройдены, детали и скрины — `results/01-network-fw.md`, `results/screens/01-*`.

## Известные проблемы и обходы
- Docker для сетей с `internal: true` сам ставит на хосте (в `DOCKER-ISOLATION-STAGE-1`, не трогая `/etc/nftables.conf`) правило, блокирующее пересылку пакета с чужим для данного bridge адресом назначения — даже если сосед по bridge является нашим контейнером-роутером. Из-за этого обошлись без `internal: true` (см. «Отступления»). Если при `docker compose up` на новой машине снова появится 100% потерь между зонами при живых маршрутах и ARP — проверить `docker network inspect gis_<сеть> --format '{{.Internal}}'`, должно быть `false`.
- `sudo` внутри Claude Code не может запросить пароль (нет tty) — диагностические/host-level команды, если понадобятся, выполнять в обычном терминале руками.

## Отступления от схемы
1. Сети `gis_ext/transit/dmz/intra` подняты **без** `internal: true`; вместо этого на каждой сети `driver_opts: com.docker.network.bridge.enable_ip_masquerade: "false"`. Причина и проверка — `results/01-network-fw.md`, раздел «Отступления от схемы и причины», п.1. Хост не менялся, только `stand/docker-compose.yml`.
2. На fw-ext DNAT-правила форварда дополнены `ct status dnat` — иначе прямой запрос на внутренний IP dmz в обход публичного адреса тоже форвардился бы. Детали — `results/01-network-fw.md`, п.2.
3. Диапазон пассивных портов FTP зафиксирован как 21100-21110 в правиле gw-dmz — нужно использовать те же порты в `vsftpd` на этапе 02.
4. В `gis-base` добавлен пакет `iputils-tracepath` (в Debian 13 он отдельно от `iputils-ping`).

## Журнал (новые записи сверху)
Формат записи: `ДАТА ВРЕМЯ — этап NN — что сделано / что сломалось / что дальше`

2026-10-30 — этап 01 — каркас стенда поднят: 4 сети, 13 узлов, маршрутизация, nftables (protect/audit) на 3 МЭ, скрипты up/down/mode/shot. Нашли и обошли блокировку форвардинга между docker internal-сетями (DOCKER-ISOLATION-STAGE-1) без правок хоста. Нашли и закрыли прямой доступ к dmz в обход DNAT (`ct status dnat`). Все проверки из `prompts/01-network-fw.md` — PASS, результаты в `results/01-network-fw.md`. Дальше: этап 02 (web/FTP/PostgreSQL).
