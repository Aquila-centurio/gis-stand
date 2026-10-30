# Этап 04 — VPN WireGuard и удалённый доступ

## Цель
Организовать защищённый удалённый доступ к внутренней сети через WireGuard (в схеме был
OpenVPN, по решению группы заменён на WireGuard) и показать, что без туннеля доступа к intra
нет, а с туннелем разрешено только то, что задано политикой (VPN-клиент → arm1 tcp 22).

## Что сделано
- На узле `vpn` (transit .3) поднят WireGuard-сервер `wg0`, адрес 10.8.0.1/24, порт udp 51820.
  Ключи (server/client/bad-client) генерируются один раз при первом запуске контейнера в
  `stand/secrets/wg/` (том, смонтирован на vpn и client, не в git), приватные ключи не выводятся
  на экран (`wg show` маскирует их всегда).
- Клиент `client` (ext .10) получил готовые конфиги `/etc/wireguard/wg0.conf` (рабочий ключ) и
  `wg0-badkey.conf` (ключ, не зарегистрированный на сервере) — собираются скриптом
  `wg-prepare.sh` из ключей на общем томе, но интерфейс не поднимается автоматически: подъём и
  отключение туннеля (`wg-quick up/down`) делает пользователь вручную, чтобы показать разницу
  до/после.
- DNAT с fw-ext на vpn:51820 и разрешающее правило в forward (`ct status dnat`) были готовы
  ещё с этапа 01 — проверены, без изменений.
- На `vpn` добавлен nftables: input — только udp/51820 и established/related, всё остальное
  (включая ssh, icmp) к самому vpn закрыто; forward — accept (фильтрация трафика VPN-клиентов
  в intra делается на `fw-int`, в dmz — на `gw-dmz`, их правила не менялись: там уже политика
  drop по умолчанию). NAT на vpn не делали — в логах/счётчиках fw-int виден настоящий адрес
  клиента в туннеле (10.8.0.x), а не адрес vpn.
- В `fw-int-protect.nft` правило `VPN-клиент (10.8.0.0/24) → arm1 (192.168.200.31) tcp/22` было
  заведено ещё на этапе 01 (комментарий «этап 04») — проверено, без изменений.
- Узел `arm1` получил заглушку с sshd (openssh-server, пользователь `armuser`, пароль из
  `ARM_SSH_PASSWORD`) — нужна как цель для проверки доступа VPN-клиента. Полноценный АРМ с
  доменом — этап 05.
- На `client` добавлены `wireguard-tools` и `openssh-client` (для реальной демонстрации ssh, а не
  только TCP-коннекта).

## Конфигурация

### vpn: nftables (`stand/nodes/vpn/nft/vpn.nft`)
```
table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;
        iif "lo" accept
        ct state established,related accept
        udp dport 51820 counter name c_vpn_in_wg accept
        counter name c_vpn_in_drop drop
    }
    chain forward {
        type filter hook forward priority 0; policy accept;
        counter name c_vpn_fwd
    }
}
```

### vpn: wg0.conf (шаблон из `entrypoint.sh`, без приватного ключа)
```
[Interface]
Address = 10.8.0.1/24
ListenPort = 51820
PrivateKey = <server.key>

[Peer]
PublicKey = <client.pub>
AllowedIPs = 10.8.0.2/32
```

### client: wg0.conf (из `wg-prepare.sh`, без приватного ключа)
```
[Interface]
PrivateKey = <client.key>
Address = 10.8.0.2/32

[Peer]
PublicKey = <server.pub>
Endpoint = 198.51.100.1:51820
AllowedIPs = 192.168.200.0/24, 10.8.0.0/24
PersistentKeepalive = 25
```

### fw-int: правило для VPN (уже было с этапа 01, полный файл `stand/nodes/fw-int/nft/fw-int-protect.nft`)
```
ip saddr 10.8.0.0/24 ip daddr 192.168.200.31 tcp dport 22 counter name c_int_vpn_to_arm accept
```

### fw-ext: DNAT и разрешение на vpn (уже было с этапа 01, полный файл `stand/nodes/fw-ext/nft/fw-ext-protect.nft`)
```
ip daddr 198.51.100.1 udp dport 51820 dnat to 192.168.50.3:51820
...
ip daddr 192.168.50.3 udp dport 51820 ct status dnat counter name c_ext_to_vpn accept
```

## Проверка функционирования

### 1 — до туннеля доступа нет
- Команда: `docker exec gis-client sh -c 'nc -vz -w3 192.168.200.31 22'`
- Ожидание: таймаут, доступа нет.
- Получили: `nc: connect to 192.168.200.31 port 22 (tcp) timed out`, `EXIT:1`.
- Скрин: `screens/04-before-tunnel.png`
- Итог: PASS

### 2 — поднятие туннеля, `wg show` на обеих сторонах
- Команда: `wg-quick up wg0` на client, затем `wg show` на vpn и на client.
- Ожидание: виден handshake, transfer, endpoint; приватные ключи не показаны.
- Получили: на vpn — `endpoint: 198.51.100.10:46580`, `latest handshake: 14 seconds ago`,
  `transfer: 676 B received, 412 B sent`, `private key: (hidden)`; на client — зеркально,
  `persistent keepalive: every 25 seconds`.
- Скрины: `screens/04-wg-show-vpn.png`, `screens/04-wg-show-client.png`
- Итог: PASS

### 3 — после туннеля: разрешено (arm1:22) и запрещено (db:5432, dc)
- Команды: `nc -vz -w3 192.168.200.31 22`; `nc -vz -w3 192.168.200.10 5432`;
  `nc -vz -w3 192.168.200.20 445`.
- Ожидание: первое — успех, остальные — таймаут (политика).
- Получили: `Connection to 192.168.200.31 22 port [tcp/*] succeeded!`; на db и dc —
  `timed out: Operation now in progress`, `EXIT:1` на обеих.
- Скрины: `screens/04-after-tunnel-arm.png`, `screens/04-after-tunnel-denied.png`
- Итог: PASS

### 4 — шифрование: снаружи только UDP, внутри открытый SSH
- Команды (во время реальной попытки `ssh armuser@192.168.200.31` с client):
  `docker exec gis-vpn tcpdump -n -i eth0 -c 20 udp port 51820` (интерфейс vpn в transit) и
  `docker exec gis-fw-int tcpdump -n -i eth0 -c 15 tcp port 22` (интерфейс fw-int в intra).
- Ожидание: на стороне vpn/transit — только UDP/51820 без признаков содержимого; на стороне
  fw-int/intra — обычный TCP с открытой строкой SSH-банера.
- Получили: на vpn — 20 пакетов `UDP, length N` между `198.51.100.10.57485` и
  `192.168.50.3.51820`, никакого TCP/SSH не видно; на fw-int — обычный TCP-хендшейк
  `10.8.0.2.35702 > 192.168.200.31.22`, видна открытым текстом строка
  `SSH: SSH-2.0-OpenSSH_10.0p2 Debian-7+deb13u4` в обе стороны (банер клиента и сервера) —
  значит дальше вглубь сети туннель WireGuard не идёт, трафик расшифрован уже на vpn, в intra
  он снова виден как обычный TCP/SSH (сам протокол SSH тоже шифрует данные пользователя своим
  слоем — это ожидаемо и отдельно от задачи VPN).
- Скрины: `screens/04-tcpdump-vpn-udp.png`, `screens/04-tcpdump-fwint-plain.png`
- Итог: PASS

### 5 — отключение туннеля
- Команда: `docker exec gis-client sh -c 'wg-quick down wg0; nc -vz -w3 192.168.200.31 22'`
- Ожидание: интерфейс удалён, доступ пропал.
- Получили: `[#] ip link delete dev wg0`, затем `timed out`, `EXIT:1`.
- Скрин: `screens/04-tunnel-down.png`
- Итог: PASS

### 6 — неверный ключ не получает handshake
- Команда: `wg-quick up wg0-badkey` (ключ `bad-client`, не добавлен в peer-лист сервера), затем
  `wg show wg0-badkey` и `nc -vz -w3 192.168.200.31 22`.
- Ожидание: `transfer` показывает только отправленные байты (0 получено), строки
  `latest handshake` нет вообще, доступа нет.
- Получили: `transfer: 0 B received, 296 B sent`, строка `latest handshake` отсутствует (при
  успешном рукопожатии она появляется); `nc` — таймаут, `EXIT:1`.
- Скрин: `screens/04-badkey-no-handshake.png`
- Итог: PASS

### 7 — `nft list ruleset` и счётчики
- Команды: `docker exec gis-vpn nft list ruleset`; `docker exec gis-fw-int nft list ruleset`.
- Ожидание: на vpn счётчик `c_vpn_in_wg` больше нуля (легитимный udp/51820), `c_vpn_in_drop`
  больше нуля (посторонний трафик к vpn, в т.ч. наш `ping` на 10.8.0.1 из проверки 3, который
  блокируется как input к самому vpn); на fw-int счётчик `c_int_vpn_to_arm` больше нуля
  (разрешённый ssh от VPN-клиента), `c_int_fwd_drop` больше нуля (попытки к db/dc).
- Получили: `c_vpn_in_wg`: 8 пакетов 1408 байт; `c_vpn_in_drop`: 1 пакет 84 байта (ровно наш
  ping); на fw-int `c_int_vpn_to_arm`: 6 пакетов 360 байт; `c_int_fwd_drop`: 6 пакетов 360 байт
  (попытки к 5432 и 445, посчитаны оба адреса).
- Скрины: `screens/04-nft-vpn.png`, `screens/04-nft-fwint-counters.png`
- Итог: PASS

## WireGuard vs OpenVPN/PPTP
В образце курса использовался OpenVPN (TLS-туннель поверх TCP/UDP, сертификаты сервера и
клиентов, демон в userspace) и в старых схемах встречается PPTP (GRE-туннель, аутентификация
MS-CHAPv2, давно взломана, по факту не шифрует надёжно). WireGuard проще и современнее: это
модуль ядра, один статический кадр handshake (Noise IK), аутентификация — только пара ключей
Curve25519 (пир добавляется по публичному ключу, без сертификатов и CA), шифрование данных —
ChaCha20-Poly1305 с перманентной прямой секретностью (новые session-ключи на каждый handshake).
Поверхность атаки меньше: сервер не отвечает вообще ничем пиру, чей публичный ключ не в его
списке (проверка 6), в отличие от OpenVPN/TLS, где уже на этапе TLS-handshake виден факт
попытки подключения. Аутентификация самого VPN — по ключам WireGuard; RADIUS в стенде
используется отдельно, для авторизации выхода АРМ в интернет через Squid (этап 05), с VPN
не связан.

## Отступления от схемы и причины
1. На `vpn` намеренно не делали masquerade/NAT для трафика из wg0: иначе на `fw-int` в счётчиках
   и в tcpdump был бы виден адрес vpn (192.168.50.3), а не реальный адрес клиента в туннеле
   (10.8.0.x) — хуже для демонстрации и для будущих логов. Правило `fw-int` на VPN-клиентов
   поэтому написано по адресам `10.8.0.0/24`, а не по адресу vpn.
2. Ключи WireGuard (server/client/bad-client) генерируются внутри контейнера `vpn` при первом
   запуске и кладутся в `stand/secrets/wg/` (том, общий с `client`), а не отдельным скриптом на
   хосте — на хосте нет пакета `wireguard-tools` и мы не ставим его туда без необходимости
   (политика проекта: ничего не менять на хосте). Идемпотентно: при повторном запуске ключи не
   перегенерируются, если файлы уже есть.
3. Третий ключ (`bad-client`) генерируется заранее на сервере вместе с остальными, но никогда не
   добавляется в peer-лист `vpn` — это и есть «неверный ключ» для проверки 6, отдельного шага
   «сгенерировать ключ и не регистрировать» не потребовалось.
4. Подъём/отключение туннеля на `client` не автоматизировали в `entrypoint.sh` — конфиги
   (`wg0.conf`, `wg0-badkey.conf`) готовятся сразу при старте контейнера, а `wg-quick up/down`
   пользователь выполняет вручную, иначе нельзя было бы показать проверку «до туннеля».
5. На `arm1` пока используется временная учётная запись `armuser` с паролем из
   `ARM_SSH_PASSWORD` (`stand/secrets/stand.env`) — полноценная интеграция с доменом `gis.local`
   и доменные пользователи появятся на этапе 05, сейчас это только цель для проверки политики
   МЭ по порту 22.

## Проблемы и как решили
- Первая попытка проверить шифрование одним `tcpdump -i eth0 -c 20` на `vpn` без фильтра показала
  вперемешку и зашифрованные udp/51820, и уже расшифрованные TCP-пакеты в сторону intra — это
  правильное поведение (vpn пересылает трафик из wg0 обратно в transit, к fw-int, через тот же
  интерфейс eth0: отдельного «внутреннего» интерфейса у vpn нет), но для чистой демонстрации
  «снаружи только UDP» захват на vpn сделали с явным фильтром `udp port 51820`, а расшифрованный
  SSH показали отдельным захватом на `fw-int` (там этого смешения уже нет, туда приходит только
  декапсулированный трафик).
- Реальный `ssh` на arm1 завершается `Permission denied (publickey,password)`, так как
  `BatchMode=yes` отключает интерактивный ввод пароля — это осознанно: нужен сам факт обмена
  баннерами SSH в открытом виде для tcpdump, а не успешный логин; `nc -vz` достаточно и отдельно
  подтверждает, что TCP-сессия на 22 проходит целиком.
