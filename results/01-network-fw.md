# Этап 01 — сети, роутеры, межсетевые экраны

## Цель
Поднять каркас стенда: 4 сети, 13 узлов (заглушки сервисов + 4 роутера: fw-ext, gw-dmz, fw-int, vpn), маршрутизацию между зонами и nftables на трёх МЭ (fw-ext, gw-dmz, fw-int) с режимами `protect`/`audit`.

## Что сделано
- Базовый образ `gis-base` (Debian 13/trixie + iproute2, nftables, iputils-ping, iputils-tracepath, curl, tcpdump, netcat-openbsd, dnsutils, procps) и 13 Dockerfile на каждый узел.
- `docker-compose.yml` проекта `gis`: 4 сети со статическими адресами (ipam), маршруты ставятся явно в entrypoint каждого узла (интерфейс ищется по подсети, не по имени `ethN`).
- nftables на fw-ext, gw-dmz, fw-int: таблицы `inet nat`/`inet filter`, политика `forward` по умолчанию `drop` + именованные счётчики на всех значимых правилах; на fw-ext — DNAT 80/443→web, 51820/udp→vpn, masquerade для исходящего от fw-int.
- Скрипты `up.sh`, `down.sh`, `mode.sh protect|audit`, `shot.sh` + `render_term.py` (venv `gis/.venv`, Pillow) для рендера скринов терминала.
- web и ftp временно — заглушки (web слушает 80 через `python3 -m http.server`); db слушает 5432 и 22 через `nc -lk`, чтобы проверять прохождение/блокировку МЭ до появления реальных сервисов в этапе 02.
- Пройдены все обязательные проверки из `prompts/01-network-fw.md` в обоих режимах.

## Фактический IP-план
| Сеть | Подсеть | Gateway (docker, не используется в маршрутах) |
|---|---|---|
| ext | 198.51.100.0/24 | 198.51.100.254 |
| transit | 192.168.50.0/24 | 192.168.50.254 |
| dmz | 192.168.100.0/24 | 192.168.100.254 |
| intra | 192.168.200.0/24 | 192.168.200.254 |

| Узел | Адреса |
|---|---|
| fw-ext | ext .1, transit .1 |
| gw-dmz | transit .2, dmz .1 |
| vpn | transit .3 |
| fw-int | transit .4, intra .1 |
| radius | transit .5 |
| web | dmz .10 |
| ftp | dmz .11 |
| db | intra .10 |
| dc | intra .20 |
| arm1 | intra .31 |
| client | ext .10 |
| attacker | ext .66 |
| inet | ext .80 |

Полностью соответствует таблице из `prompts/00-context.md`.

## Конфигурация

### nftables fw-ext (protect), ключевые правила
Полный файл: `stand/nodes/fw-ext/nft/fw-ext-protect.nft`
```
chain forward {
    type filter hook forward priority 0; policy drop;
    ct state established,related accept
    ct state invalid counter name c_ext_invalid drop
    ip daddr 192.168.100.10 tcp dport { 80, 443 } ct status dnat counter name c_ext_to_web accept
    ip daddr 192.168.50.3 udp dport 51820 ct status dnat counter name c_ext_to_vpn accept
    ip saddr 192.168.50.4 tcp dport { 80, 443 } counter name c_ext_fwint_out accept
    counter name c_ext_fwd_drop drop
}
```
«Зачем»: `ct status dnat` — пропускать в dmz/к vpn только пакеты, реально прошедшие трансляцию с публичного адреса 198.51.100.1, а не любой пакет, адресованный напрямую на внутренний IP (см. «Проблемы и как решили»). Правило `ip saddr 192.168.50.4 ...` — исходящий трафик только от fw-int (после Squid в этапе 05).

### nftables gw-dmz (protect)
Полный файл: `stand/nodes/gw-dmz/nft/gw-dmz-protect.nft`
```
chain forward {
    type filter hook forward priority 0; policy drop;
    ct state established,related accept
    ct state invalid counter name c_dmz_invalid drop
    ip daddr 192.168.100.10 tcp dport { 80, 443 } counter name c_dmz_to_web accept
    ip saddr 192.168.200.0/24 ip daddr 192.168.100.11 tcp dport { 21, 21100-21110 } counter name c_dmz_to_ftp accept
    ip saddr 192.168.100.10 ip daddr 192.168.200.10 tcp dport 5432 counter name c_dmz_web_to_db accept
    counter name c_dmz_fwd_drop drop
}
```
«Зачем»: диапазон пассивных портов ftp 21100-21110 выбран сейчас, чтобы на этапе 02 настроить `vsftpd` с теми же `pasv_min_port/pasv_max_port`.

### nftables fw-int (protect)
Полный файл: `stand/nodes/fw-int/nft/fw-int-protect.nft`
```
chain forward {
    type filter hook forward priority 0; policy drop;
    ct state established,related accept
    ct state invalid counter name c_int_invalid drop
    ip saddr 192.168.100.10 ip daddr 192.168.200.10 tcp dport 5432 counter name c_int_web_to_db accept
    ip saddr 10.8.0.0/24 ip daddr 192.168.200.31 tcp dport 22 counter name c_int_vpn_to_arm accept
    ip saddr 192.168.200.31 ip daddr 192.168.100.10 tcp dport { 80, 443 } counter name c_int_arm_to_web accept
    ip saddr 192.168.200.31 ip daddr 192.168.100.11 tcp dport 21 counter name c_int_arm_to_ftp accept
    counter name c_int_fwd_drop drop
}
```
«Зачем»: правило для VPN-клиентов (10.8.0.0/24 → arm1:22) и правило для Squid на fw-int (intra → интернет) добавятся предметно в этапах 04/05, сейчас заложены адреса по схеме, чтобы не трогать файл правил повторно.

### Режим audit
Для каждого МЭ отдельный файл `*-audit.nft`: `nat`-таблица (где есть) не меняется, `filter.forward` переключается в `policy accept` с одним общим счётчиком — ACL не действует, но маршрутизация, DNAT, счётчики и (в будущем) IDS продолжают работать. `mode.sh` переключает режим через `nft -f /etc/nft/<role>-<mode>.nft` (файл начинается с `flush ruleset`, поэтому переприменение идемпотентно) — без перезапуска контейнеров.

## Проверка функционирования

### Проверка 1 — protect: ping attacker → dmz и intra
- Команда: `docker exec gis-attacker ping -c3 -W1 192.168.100.10` и `... 192.168.200.10`
- Ожидание: 100% потерь в обоих случаях.
- Получили: 100% packet loss в обоих случаях (ICMP не входит ни в одно allow-правило).
- Скрин: screens/01-ping-attacker-dmz.png, screens/01-ping-attacker-intra.png
- Итог: PASS

### Проверка 2 — protect: curl client → публичный адрес (DNAT)
- Команда: `docker exec gis-client curl -sS -m5 http://198.51.100.1`
- Ожидание: ответ веб-заглушки.
- Получили: HTML-страница `web` (200 OK, DNAT 198.51.100.1:80 → 192.168.100.10:80 сработал).
- Скрин: screens/01-curl-client-web.png
- Итог: PASS

### Проверка 3 — protect: прямой доступ к dmz в обход публичного адреса
- Команда: `docker exec gis-attacker nmap -sT -Pn -T4 -p 21,22,80,443,5432 192.168.100.10 192.168.100.11`
- Ожидание: все порты filtered (dmz не должна быть доступна напрямую по внутреннему IP, только через 198.51.100.1).
- Получили: до фикса `ct status dnat` порт 80 на web светился `open` при прямом обращении к 192.168.100.10 — нашли и закрыли (см. «Проблемы и как решили»). После фикса: все порты `filtered` на обоих хостах.
- Скрин: screens/01-nmap-dmz-direct.png
- Итог: PASS (после исправления правила)

### Проверка 4 — protect: attacker → 198.51.100.1 порты 21,22,443,5432 закрыты
- Команда: `docker exec gis-attacker nmap -sT -Pn -T4 -p 21,22,80,443,5432 198.51.100.1`
- Ожидание: 21,22,443,5432 closed, 80 open.
- Получили: 21/closed, 22/closed, 80/open, 443/closed, 5432/closed.
- Скрин: screens/01-nmap-public-closed.png
- Итог: PASS

### Проверка 5 — protect: web → db:5432 проходит
- Команда: `docker exec gis-web sh -c 'echo | timeout 3 nc -zv 192.168.200.10 5432'`
- Ожидание: `succeeded`.
- Получили: `Connection to 192.168.200.10 5432 port [tcp/postgresql] succeeded!`
- Скрин: screens/01-nc-web-db-5432.png
- Итог: PASS

### Проверка 6 — protect: web → db:22 не проходит
- Команда: `docker exec gis-web sh -c 'echo | timeout 3 nc -zv 192.168.200.10 22'`
- Ожидание: таймаут (drop, без ответа).
- Получили: команда отработала по таймауту 3 с без вывода об успехе (пакет дропнут и на gw-dmz, и не дошёл до fw-int).
- Скрин: screens/01-nc-web-db-22.png
- Итог: PASS

### Проверка 7 — protect: ftp → db не проходит
- Команда: `docker exec gis-ftp sh -c 'echo | timeout 3 nc -zv 192.168.200.10 5432'`
- Ожидание: таймаут.
- Получили: таймаут, соединение не установлено.
- Скрин: screens/01-nc-ftp-db.png
- Итог: PASS

### Проверка 8 — nft list ruleset и счётчики (после проверок 1-7)
- Команда: `docker exec gis-<fw-ext|gw-dmz|fw-int> nft list ruleset`
- Ожидание: видны правила и ненулевые счётчики на drop-правилах.
- Получили: `c_ext_fwd_drop` 34 пакета, `c_dmz_fwd_drop` 6 пакетов (icmp-пинги, сканы, прямой web:22/443/5432, web→db:22, ftp→db), `c_ext_to_web`/`c_dmz_to_web`/`c_int_web_to_db` по 1-3 пакета — легитимный трафик прошёл, запрещённый — дропнут и посчитан.
- Скрин: screens/01-nft-fwext.png, screens/01-nft-gwdmz.png, screens/01-nft-fwint.png
- Итог: PASS

### Проверка 9 — audit: ping attacker → intra проходит
- Команда: `./stand/scripts/mode.sh audit`, затем `docker exec gis-attacker ping -c3 -W1 192.168.200.10`
- Ожидание: 0% потерь (ACL не применяется).
- Получили: 0% packet loss.
- Скрин: screens/01-audit-ping-attacker-intra.png
- Итог: PASS

### Проверка 10 — mode.sh переключает туда-обратно без перезапуска, до/после на одной проверке
- Команда: один скрипт — ping в audit, `mode.sh protect`, тот же ping снова (контейнеры не перезапускались, `docker compose ps` между шагами не менялся).
- Ожидание: audit — проходит (0% потерь), после переключения в protect — не проходит (100% потерь).
- Получили: ровно так.
- Скрин: screens/01-mode-before-after.png
- Итог: PASS

### Проверка 11 — audit: tracepath client → db, маршрут через зоны
- Команда: `docker exec gis-client tracepath -n 192.168.200.10`
- Ожидание: путь виден через несколько хопов.
- Получили: `198.51.100.1 (fw-ext) → 192.168.50.4 (fw-int) → 192.168.200.10 (db), reached`. gw-dmz в пути нет — он не нужен для маршрута ext↔intra (есть прямой маршрут через fw-int), соответствует таблице маршрутов.
- Скрин: screens/01-audit-tracepath-client-db.png
- Итог: PASS

### Проверка 12 — ip route на всех роутерах
- Команда: `ip route` на fw-ext, gw-dmz, fw-int, vpn.
- Ожидание: соответствие таблице маршрутов из `00-context.md` (fw-ext без default, остальные — default через fw-ext + явные маршруты к недостающим подсетям).
- Получили: полностью совпадает.
- Скрин: screens/01-routes-all.png
- Итог: PASS

## Отступления от схемы и причины

1. **Сети без `internal: true`, вместо этого `driver_opts: com.docker.network.bridge.enable_ip_masquerade: "false"` на каждой из 4 сетей.**
   Причина: при `internal: true` Docker сам добавляет на хосте (в цепочку `DOCKER-ISOLATION-STAGE-1`, управляется dockerd, не из `/etc/nftables.conf`) правило вида `ip daddr != <подсеть-этого-bridge> iifname "br-..." drop` — оно глушит пересылку пакета, даже если он адресован соседнему контейнеру-роутеру, который готов переслать его дальше в другую docker-сеть. Это ломает саму идею стенда (роутеры должны пересылать трафик между зонами). Проверено на реальном `sudo nft list ruleset` хоста (см. диагностику сессии) — счётчик drop-правила для `br-c87ef97ff3c7` (сеть `ext`) инкрементировался ровно на тестовый трафик. Убрали `internal: true` и explicitly выключили NAT-маскарад (`enable_ip_masquerade: "false"`) на каждой сети — так Docker не создаёт этот блокирующий per-subnet drop и не поднимает masquerade наружу; выход в реальный интернет проверен — его нет (`curl https://1.1.1.1` из client — таймаут). Все 4 сети по-прежнему полностью изолированы от хоста и друг от друга, кроме явной маршрутизации через наши контейнеры-роутеры. Правка только в `stand/docker-compose.yml`, хост не менялся.
2. **Правило DNAT-доступа на fw-ext дополнено `ct status dnat`.**
   Без этого условия правило `ip daddr 192.168.100.10 tcp dport {80,443} accept` пропускало бы любой пакет с таким daddr, включая отправленный attacker напрямую на внутренний IP dmz в обход публичного адреса 198.51.100.1 (нашли через nmap в проверке 3, см. ниже).
3. **web/ftp/db/dc/arm1/radius/vpn — временные заглушки** без реальных сервисов (появятся в этапах 02-05), как и предусмотрено планом.
4. **Пакет `iputils-tracepath` добавлен в `gis-base` явно** — в Debian 13 `tracepath` вынесен из `iputils-ping` в отдельный пакет.
5. **Диапазон пассивных портов FTP выбран как 21100-21110** (в правиле gw-dmz) — фиксируем сейчас, чтобы в этапе 02 настроить `vsftpd` с этими же `pasv_min_port/pasv_max_port` без повторной правки firewall.

## Проблемы и как решили

1. **Именованные nftables-счётчики не применялись** (`Error: Could not process rule: No such file or directory`). Причина: `counter name X` в правиле требует, чтобы объект-счётчик `X` был заранее объявлен в таблице (`counter X {}`), простого упоминания в правиле недостаточно. Добавили блок объявлений счётчиков в начало каждой таблицы `inet filter` во всех `*.nft` файлах.
2. **Пересылка между зонами не работала вообще** (ни ping, ни curl, пакет уходил с роутера, но физически не приходил на интерфейс соседнего роутера, хотя ARP резолвился и прямой ping между самими роутерами проходил). Долгая диагностика: `tcpdump` на обоих концах транзитного сегмента показал, что кадр покидает исходный контейнер, но не появляется на интерфейсе соседнего. Подтверждено чтением `sudo nft list ruleset` на хосте (с разрешения пользователя) — причина в `DOCKER-ISOLATION-STAGE-1`, которую dockerd создаёт для `internal: true`-сетей. Решение — отступление №1 выше (без правок на хосте).
3. **Прямой доступ к dmz в обход публичного IP** — см. отступление №2 выше, нашли через nmap, исправили правилом `ct status dnat`.

## Коммит
Сделан `git init` в `gis/` (репозиторий ещё не существовал) и первый коммит с полным содержимым этапа 01.
