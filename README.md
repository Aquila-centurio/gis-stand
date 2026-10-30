# Стенд ГИС «АУО» (вариант 3, ПАСОИБ, УрФУ)

Учебный стенд ГИС «Сайт Счётной палаты РФ» на Docker Compose (проект `gis`, 13 контейнеров, Debian 13). Только открытое ПО: nftables, Suricata, WireGuard, Squid, FreeRADIUS, Samba AD, PostgreSQL, Apache+PHP, vsftpd. Схема: `docs/scheme-gis-auo.png`.

Пароли и ключи WireGuard лежат в `stand/secrets/` и закоммичены намеренно: стенд учебный, в реальных системах так делать нельзя.

## Что нужно
- Linux с Docker и плагином `docker compose` (пользователь в группе `docker`).
- Место под образы 13 узлов. Первая сборка идёт несколько минут.
- Хост не трогаем: правила и sysctl настраиваются только внутри контейнеров.

## Запуск
```
cd stand
scripts/up.sh      # собирает образы и поднимает стенд (с нуля или поверх)
scripts/down.sh    # остановка с удалением томов (docker compose down -v), домен создастся заново
```
Домен `gis.local` провизируется при первом старте, arm1 входит в него сам. Дайте стенду 1-2 минуты, пока dc и arm1 станут готовы.

## Режимы межсетевых экранов
```
scripts/mode.sh protect   # по умолчанию: политика drop, разрешено только нужное
scripts/mode.sh audit     # ACL выключены (для внешнего аудита), маршрутизация, IDS и логи работают
```

## Проверка и демонстрация
```
scripts/check-all.sh      # 48 автопроверок этапов 01-05, итог в results/06-checks.txt
scripts/demo.sh           # демонстрация для защиты, шаги по Enter
```

## Полезные команды
```
docker exec -it gis-attacker bash     # внешний нарушитель (nmap, curl)
docker exec -it gis-client bash       # удалённый пользователь (wg-quick up wg0)
docker exec -it gis-arm1 bash         # АРМ, клиент домена
docker exec gis-gw-dmz cat /var/log/suricata/fast.log    # алерты IDS
scripts/shot.sh <имя> <команда>       # скрин терминала в results/screens/
```
Логи Suricata также на хосте: `stand/logs/gw-dmz/`. Чистый перезапуск: `scripts/down.sh`, затем `scripts/up.sh`.

## Что где лежит
| Путь | Что там |
|---|---|
| `stand/docker-compose.yml`, `stand/nodes/<узел>/` | описание стенда и конфиги узлов |
| `stand/scripts/` | up, down, mode, check-all, demo, shot |
| `stand/secrets/` | учебные пароли (`stand.env`) и ключи WireGuard |
| `results/` | результаты этапов 01-06 для отчёта, `00-summary.md` — общая сводка, `screens/` — скрины и их текст |
| `prompts/` | задания по этапам и общий контекст (`00-context.md`) |
| `PROGRESS.md` | журнал работы и текущее состояние |
| `docs/` | схемы и исходные материалы |

## Что делать команде
1. Поднять стенд и прогнать `scripts/check-all.sh`, убедиться, что все 48 проверок PASS.
2. Прочитать `results/00-summary.md`: топология, IP-план, замены относительно схемы, матрица проверок.
3. Оформить отчёт в Word по образцу из `docs/` на основе `results/NN-*.md` и скринов из `results/screens/`.
4. Подготовиться к защите: пройти `scripts/demo.sh`, знать, какой механизм что защищает и чем заменили Windows и Secret Net.

Сдача: суббота 7 ноября 2026, 00:00.
