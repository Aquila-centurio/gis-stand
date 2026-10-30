#!/usr/bin/env bash
# Демонстрация стенда ГИС на защите, 5-7 минут. Между шагами пауза до Enter.
# Для сухого прогона без паузы: yes '' | stand/scripts/demo.sh | tee results/06-demo-run.txt
# Пароли берутся из окружения контейнеров и в вывод не попадают.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
STAND_DIR="$SCRIPT_DIR/.."
FAST_LOG="$STAND_DIR/logs/gw-dmz/fast.log"
SSH_OPTS='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5'

if [[ -t 1 ]]; then B=$'\e[1;36m'; D=$'\e[0m'; else B=''; D=''; fi

trap '"$SCRIPT_DIR/mode.sh" protect >/dev/null 2>&1; docker exec gis-client wg-quick down wg0 >/dev/null 2>&1; true' EXIT

step() { echo; echo "${B}=== $1 ===${D}"; echo "$2"; }
pause() { read -r -p "[Enter: дальше] " _ || true; echo; }
# run 'команда': показывает команду и выполняет её (ошибка команды не останавливает демо)
run() { echo "\$ $1"; bash -c "$1" 2>&1 || echo "(код выхода: $?)"; }

echo "${B}Стенд ГИС «АУО» (вариант 3): демонстрация${D}"
"$SCRIPT_DIR/mode.sh" protect >/dev/null
docker exec gis-client wg-quick down wg0 >/dev/null 2>&1 || true
echo "Режим МЭ: protect"
pause

step "1. Схема и состояние узлов" "13 контейнеров в 4 docker-сетях: ext (интернет), transit (общий коммутатор), dmz, intra."
run "docker ps --filter name=gis- --format '{{.Names}}\t{{.Status}}' | sort"
run "for c in fw-ext gw-dmz vpn fw-int radius web ftp db dc arm1 client attacker inet; do printf '%-10s' \$c; docker inspect -f '{{range \$k,\$v := .NetworkSettings.Networks}}{{\$k}}={{\$v.IPAddress}} {{end}}' gis-\$c; done"
pause

step "2. Межсетевой экран: снаружи сайт открывается, всё остальное закрыто" "Режим protect: политика drop по умолчанию, наружу опубликованы только 80/443 (DNAT на web) и udp/51820 (VPN)."
run "docker exec gis-attacker ping -c2 -W1 192.168.100.10"
run "docker exec gis-attacker ping -c2 -W1 192.168.200.10"
run "docker exec gis-client curl -sS -m5 -o /dev/null -w 'http://198.51.100.1/ -> HTTP %{http_code}, редирект: %{redirect_url}\n' http://198.51.100.1/"
run "docker exec gis-client curl -k -sS -m5 https://198.51.100.1/ | grep -o '<title>[^<]*</title>'"
run "docker exec gis-fw-ext nft list ruleset | grep -E 'dnat|counter' | head -8"
pause

step "3. Два режима: audit и protect" "audit: ACL не применяются, но маршрутизация, DNAT, IDS и логи работают (нужно для внешнего аудита)."
run "'$SCRIPT_DIR/mode.sh' audit | tail -1"
run "docker exec gis-attacker ping -c2 -W1 192.168.200.10"
run "'$SCRIPT_DIR/mode.sh' protect | tail -1"
run "docker exec gis-attacker ping -c2 -W1 192.168.200.10"
pause

step "4. IDS Suricata: XSS в запросе даёт алерт" "Запрос идёт по http://, чтобы payload был виден пассивному IDS (HTTPS шифрует его, см. results/03-ids.md)."
before=$(grep -c '1:1000004:' "$FAST_LOG" 2>/dev/null || true)
run "docker exec gis-attacker curl -sS -m5 'http://198.51.100.1/search.php?q=%3Cscript%3Ealert(1)%3C/script%3E' | grep -o 'script[^<]*' | head -2"
echo "Ждём алерт в fast.log (до 20 с)..."
for _ in $(seq 1 20); do
    [[ "$(grep -c '1:1000004:' "$FAST_LOG" 2>/dev/null || true)" -gt "$before" ]] && break
    sleep 1
done
run "grep '1:1000004:' '$FAST_LOG' | tail -2 | cut -c1-200"
pause

step "5. VPN WireGuard: до и после туннеля" "Политика: VPN-клиенту (10.8.0.0/24) разрешён только arm1:22."
run "docker exec gis-client sh -c 'nc -vz -w3 192.168.200.31 22; echo EXIT:\$?'"
run "docker exec gis-client wg-quick up wg0 2>&1 | grep -E 'interface|address' "
run "docker exec gis-client sh -c 'nc -vz -w3 192.168.200.31 22; echo EXIT:\$?'"
run "docker exec gis-client sh -c 'nc -vz -w3 192.168.200.10 5432; echo EXIT:\$?'"
run "docker exec gis-vpn wg show wg0 | grep -E 'peer|endpoint|handshake|transfer' | sed 's/^peer: .*/peer: (ключ скрыт)/'"
run "docker exec gis-client wg-quick down wg0 2>&1 | tail -1"
pause

step "6. Домен gis.local: вход доменного пользователя на АРМ" "arm1 введён в домен Samba AD; войти могут только группы Admin и Workgroup."
run "docker exec gis-arm1 bash -c 'sshpass -p \"\$DOMAIN_USER_PASSWORD\" ssh $SSH_OPTS archstaff1@localhost \"id; hostname -f; klist | sed -n 2p\"'"
run "docker exec gis-arm1 bash -c 'sshpass -p \"\$DC_ADMIN_PASSWORD\" ssh $SSH_OPTS Administrator@localhost id; echo \"Administrator (не в Admin/Workgroup): код ssh \$?\"'"
pause

step "7. RADIUS и Squid: 407, затем 200" "Выход из intra в «интернет» только через Squid fw-int:3128 с авторизацией на RADIUS."
run "docker exec gis-arm1 curl -s -m5 -o /dev/null -w 'напрямую без прокси: HTTP %{http_code}\n' http://198.51.100.80/"
run "docker exec gis-arm1 curl -s -o /dev/null -w 'через Squid без учётки: HTTP %{http_code}\n' -x http://192.168.200.1:3128 http://198.51.100.80/"
run "docker exec gis-arm1 bash -c 'curl -s -o /dev/null -w \"через Squid с учёткой archstaff1: HTTP %{http_code}\n\" -x http://192.168.200.1:3128 -U \"archstaff1:\$PROXY_USER_PASSWORD\" http://198.51.100.80/'"
run "docker exec gis-radius grep 'Auth:' /var/log/freeradius/radius.log | tail -2"
run "docker exec gis-fw-int tail -3 /var/log/squid/access.log"

echo
echo "${B}Демонстрация завершена. Режим МЭ: protect.${D}"
