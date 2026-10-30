# Проверка окружения

## Хост
- ОС: Debian GNU/Linux 13 (trixie), ядро `6.12.111+deb13-amd64`.
- Диск (`/`): 198G всего, занято 84G, свободно 104G (45%).
- RAM: 14Gi всего, свободно 1,1Gi, available 7,7Gi, swap 4,0Gi (не используется).

## Docker
- Docker Client/Server: `26.1.5+dfsg1`, API 1.45.
- Docker Compose: `2.26.1-4`.

## nftables
- Модуль `nf_tables` загружен в хостовом ядре (`lsmod | grep nf_tables` — есть, с `nft_compat`, `nft_chain_nat`).
- В контейнере `debian:trixie` с `apt-get install nftables`: `nft --version` → `nftables v1.1.3`. Создание таблицы/цепочки и `nft list ruleset` работают без проблем.

## WireGuard-интерфейс в контейнере
- В контейнере `debian:trixie` с `--cap-add NET_ADMIN` и установленным `iproute2`:
  `ip link add wgtest type wireguard` — выполнилось без ошибок.
  `ip link show wgtest` → `wgtest: <POINTOPOINT,NOARP> mtu 1420 ... link/none`.
  `ip link del wgtest` — выполнилось.
- Вывод: хостовое ядро поддерживает wireguard как встроенный модуль, контейнеру достаточно `NET_ADMIN` (без `--privileged`).

## Базовый образ
- `debian:trixie` (Debian 13) уже есть локально (`docker images`), тянется без проблем. Используем его как базу для `gis-base`, как и решено в `00-context.md`. Отступления от `debian:12` не требуется.

## Git
- Папка `gis/` не была git-репозиторием — сделаем `git init` при первом коммите этапа.

## Вывод
Всё необходимое для этапа 01 доступно: docker/compose, nftables, wireguard-интерфейс в контейнере под `NET_ADMIN`, диск и память в достатке. Останавливаться и спрашивать пользователя не требуется, продолжаем этап 01.
