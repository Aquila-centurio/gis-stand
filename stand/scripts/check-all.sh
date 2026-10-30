#!/usr/bin/env bash
# Неинтерактивный прогон ключевых проверок этапов 01-05.
# Результат: таблица PASS/FAIL в results/06-checks.txt, код возврата 1 при любом FAIL.
# Пароли берём из переменных окружения внутри контейнеров, наружу они не выводятся.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
STAND_DIR="$SCRIPT_DIR/.."
GIS_DIR="$STAND_DIR/.."
OUT="$GIS_DIR/results/06-checks.txt"
FAST_LOG="$STAND_DIR/logs/gw-dmz/fast.log"
RESULTS=()
FAILS=0

dx() { local c="$1"; shift; docker exec "gis-$c" "$@"; }
dsh() { local c="$1"; shift; docker exec "gis-$c" bash -c "$*"; }

# Любой выход (в том числе по Ctrl+C) оставляет стенд в режиме protect и без поднятых туннелей.
cleanup() {
    "$SCRIPT_DIR/mode.sh" protect >/dev/null 2>&1 || true
    dsh client 'wg-quick down wg0 >/dev/null 2>&1; wg-quick down wg0-badkey >/dev/null 2>&1' || true
    dsh arm1 'faillock --user archstaff1 --reset' >/dev/null 2>&1 || true
}
trap cleanup EXIT

check() {
    local id="$1" desc="$2" fn="$3" status
    if "$fn" >/dev/null 2>&1; then status=PASS; else status=FAIL; FAILS=$((FAILS + 1)); fi
    RESULTS+=("$(printf '%-6s %-5s %s' "$id" "$status" "$desc")")
    printf '%-6s %-5s %s\n' "$id" "$status" "$desc"
}

SSH_OPTS='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5'

# ---------- Этап 01: сети и МЭ (protect) ----------
t01_1() { ! dx attacker ping -c2 -W1 192.168.100.10; }
t01_2() { ! dx attacker ping -c2 -W1 192.168.200.10; }
t01_3() { [[ "$(dx client curl -sS -m5 -o /dev/null -w '%{http_code}' http://198.51.100.1/)" =~ ^(200|301)$ ]]; }
t01_4() { ! dx attacker nc -z -w2 198.51.100.1 22; }
t01_5() { ! dx attacker nc -z -w2 192.168.100.10 443; }
t01_6() { dx web nc -z -w3 192.168.200.10 5432; }
t01_7() { ! dx web nc -z -w3 192.168.200.10 22; }
t01_8() { ! dx ftp nc -z -w3 192.168.200.10 5432; }
t01_9() {
    dx gw-dmz ip route | grep -q '192.168.200.0/24' && dx fw-ext ip route | grep -q '10.8.0.0/24' \
        && dx fw-int ip route | grep -q 'default'
}
t01_10() {
    "$SCRIPT_DIR/mode.sh" audit >/dev/null && dx attacker ping -c2 -W1 192.168.200.10
    local rc=$?
    "$SCRIPT_DIR/mode.sh" protect >/dev/null
    return $rc
}
t01_11() { ! dx attacker ping -c2 -W1 192.168.200.10; }

# ---------- Этап 02: web, FTP, БД ----------
t02_1() { dx client curl -sS -I -m5 http://198.51.100.1/ | grep -qE '^HTTP/.* 301'; }
t02_2() { [[ "$(dx client curl -k -sS -m5 -o /dev/null -w '%{http_code}' https://198.51.100.1/news.php)" == 200 ]]; }
t02_3() {
    dx client curl -k -sS -m5 'https://198.51.100.1/search.php?q=%3Cscript%3Ealert(1)%3C/script%3E' \
        | grep -q '<script>alert(1)</script>'
}
t02_4() {
    local out
    out=$(dx db curl -sS -m5 ftp://192.168.100.11/ 2>&1)
    grep -q 'Access denied: 530' <<<"$out"
}
t02_5() { dx db backup.sh; }
t02_6() {
    dsh web 'php -r '"'"'$c=pg_connect("host=192.168.200.10 port=5432 dbname=site user=webapp password=".getenv("WEBAPP_DB_PASSWORD")." connect_timeout=3"); $r=pg_query($c,"SELECT count(*) FROM news"); exit($r?0:1);'"'"
}
t02_7() {
    dsh web 'php -r '"'"'$c=pg_connect("host=192.168.200.10 port=5432 dbname=site user=webapp password=".getenv("WEBAPP_DB_PASSWORD")." connect_timeout=3"); $r=@pg_query($c,"SELECT * FROM internal_notes"); exit($r?1:0);'"'"
}
t02_8() {
    "$SCRIPT_DIR/mode.sh" audit >/dev/null
    local out
    out=$(docker exec -e PGCONNECT_TIMEOUT=5 gis-ftp psql -w -h 192.168.200.10 -U webapp -d site -c 'SELECT 1;' 2>&1)
    "$SCRIPT_DIR/mode.sh" protect >/dev/null
    grep -q 'pg_hba.conf rejects' <<<"$out"
}
# Осиротевший процесс в контейнере ftp: без init: true его SIGCHLD ронял vsftpd (PID 1) с кодом 139.
t02_9() {
    dx ftp sh -c 'sleep 1 & exit 0' && sleep 3 \
        && [[ "$(docker inspect -f '{{.State.Status}}' gis-ftp)" == running ]] && t02_4
}

# ---------- Этап 03: Suricata ----------
alerts() { grep -c "\[1:$1:" "$FAST_LOG" 2>/dev/null || true; }
# alert_after SID команда...: счётчик алертов SID должен вырасти после команды
alert_after() {
    local sid="$1"; shift
    local before after
    before=$(alerts "$sid")
    "$@" >/dev/null 2>&1 || true
    # Suricata иногда записывает алерт с задержкой в несколько секунд, поэтому опрашиваем до 20 с.
    for _ in $(seq 1 20); do
        after=$(alerts "$sid")
        [[ "$after" -gt "$before" ]] && return 0
        sleep 1
    done
    return 1
}
t03_1() { alert_after 1000004 dx attacker curl -sS -m5 'http://198.51.100.1/search.php?q=%3Cscript%3Ealert(1)%3C/script%3E'; }
t03_2() { alert_after 1000005 dx attacker curl -sS -m5 'http://198.51.100.1/search.php?q=%27%20OR%201%3D1--'; }
t03_3() { alert_after 1000006 dx attacker curl -sS -m5 'http://198.51.100.1/search.php?q=1%20UNION%20SELECT%201'; }
t03_4() { alert_after 1000003 dx client curl -k -sS -m5 -o /dev/null https://198.51.100.1/; }
t03_5() { alert_after 1000008 dx db backup.sh; }
# ICMP и сканирование доходят до gw-dmz в нужном объёме только в audit (см. results/03-ids.md)
t03_6() {
    "$SCRIPT_DIR/mode.sh" audit >/dev/null
    alert_after 1000001 dx attacker ping -c3 -W2 192.168.100.10
    local rc=$?
    "$SCRIPT_DIR/mode.sh" protect >/dev/null
    return $rc
}
t03_7() {
    "$SCRIPT_DIR/mode.sh" audit >/dev/null
    alert_after 1000007 dx attacker nmap -sS -Pn -T4 -p 1-200 192.168.100.10
    local rc=$?
    "$SCRIPT_DIR/mode.sh" protect >/dev/null
    return $rc
}

# ---------- Этап 04: WireGuard ----------
t04_1() { dsh client 'wg-quick down wg0 >/dev/null 2>&1; ! nc -z -w3 192.168.200.31 22'; }
t04_2() { dsh client 'wg-quick up wg0 >/dev/null 2>&1; nc -z -w3 192.168.200.31 22'; }
t04_3() { dsh client '! nc -z -w3 192.168.200.10 5432 && ! nc -z -w3 192.168.200.20 445'; }
t04_4() { dsh client 'wg show wg0 latest-handshakes | awk "{exit !(\$2 > 0)}"'; }
t04_5() { dsh vpn 'wg show wg0 latest-handshakes | awk "{exit !(\$2 > 0)}"'; }
t04_6() { dsh client 'wg-quick down wg0 >/dev/null 2>&1; ! nc -z -w3 192.168.200.31 22'; }
t04_7() {
    dsh client 'wg-quick up wg0-badkey >/dev/null 2>&1; ! nc -z -w3 192.168.200.31 22 && wg show wg0-badkey latest-handshakes | awk "{exit !(\$2 == 0)}"; rc=$?; wg-quick down wg0-badkey >/dev/null 2>&1; exit $rc'
}

# ---------- Этап 05: домен, АРМ, RADIUS, Squid, аналоги Secret Net ----------
t05_1() { dx dc samba-tool domain info 127.0.0.1 | grep -q 'gis.local'; }
t05_2() { dx arm1 adcli testjoin --domain=gis.local; }
t05_3() {
    dsh arm1 "sshpass -p \"\$DOMAIN_USER_PASSWORD\" ssh $SSH_OPTS archstaff1@localhost id | grep -q workgroup"
}
t05_4() {
    dsh arm1 "sshpass -p \"\$DOMAIN_USER_PASSWORD\" ssh $SSH_OPTS sysadmin@localhost true \
        && ! sshpass -p \"\$DC_ADMIN_PASSWORD\" ssh $SSH_OPTS Administrator@localhost true"
}
t05_5() {
    dsh arm1 "faillock --user archstaff1 --reset
        for i in 1 2 3; do sshpass -p WrongPass2026 ssh $SSH_OPTS -o NumberOfPasswordPrompts=1 archstaff1@localhost true; done
        if sshpass -p \"\$DOMAIN_USER_PASSWORD\" ssh $SSH_OPTS archstaff1@localhost true; then exit 1; fi
        faillock --user archstaff1 --reset
        sshpass -p \"\$DOMAIN_USER_PASSWORD\" ssh $SSH_OPTS archstaff1@localhost true"
}
t05_6() { ! dx dc samba-tool user create testweak qwerty12; }
t05_7() {
    dsh fw-int 'radtest archstaff1 "$PROXY_USER_PASSWORD" 192.168.50.5 0 "$RADIUS_SECRET" | grep -q Access-Accept \
        && radtest archstaff1 WrongPass123 192.168.50.5 0 "$RADIUS_SECRET" | grep -q Access-Reject \
        && radtest guest Guest2026stand 192.168.50.5 0 "$RADIUS_SECRET" | grep -q Access-Reject'
}
t05_8() {
    dsh arm1 'P=http://192.168.200.1:3128
        [ "$(curl -s -o /dev/null -w "%{http_code}" -x $P http://198.51.100.80/)" = 407 ] || exit 1
        [ "$(curl -s -o /dev/null -w "%{http_code}" -x $P -U archstaff1:WrongPass123 http://198.51.100.80/)" = 407 ] || exit 1
        [ "$(curl -s -o /dev/null -w "%{http_code}" -x $P -U "archstaff1:$PROXY_USER_PASSWORD" http://198.51.100.80/)" = 200 ]'
}
t05_9() { ! dx arm1 curl -s -m5 -o /dev/null http://198.51.100.80/; }
t05_10() {
    dsh arm1 "sshpass -p \"\$DOMAIN_USER_PASSWORD\" ssh $SSH_OPTS archstaff1@localhost 'echo test > /srv/archive/check-all.txt' \
        && ! sshpass -p \"\$DOMAIN_USER_PASSWORD\" ssh $SSH_OPTS sysadmin@localhost 'echo test > /srv/archive/check-all-sys.txt'
        rc=\$?; rm -f /srv/archive/check-all.txt; exit \$rc"
}
t05_11() {
    # Меняем содержимое отслеживаемого файла, ловим, возвращаем содержимое и mtime обратно.
    dsh arm1 'C="aide -c /etc/aide/aide-gis.conf --check"
        $C >/dev/null || exit 1
        cp -p /etc/krb5.conf /root/krb5.conf.bak; echo "# check-all" >> /etc/krb5.conf
        $C >/dev/null; rc=$?
        cp -p /root/krb5.conf.bak /etc/krb5.conf; rm -f /root/krb5.conf.bak
        [ $rc -eq 4 ] && $C >/dev/null'
}
t05_12() {
    dsh arm1 'cd /srv; printf "%s" "X5O!P%@AP[4\PZX54(P^)7CC)7}\$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!\$H+H*" > eicar.com
        echo doc > doc.txt; clamscan eicar.com doc.txt | grep -q "eicar.com: .*FOUND"; rc=$?
        clamscan doc.txt >/dev/null || rc=1; rm -f eicar.com doc.txt; exit $rc'
}
t05_13() {
    dsh client "wg-quick up wg0 >/dev/null 2>&1
        sshpass -p \"\$DOMAIN_USER_PASSWORD\" ssh $SSH_OPTS archstaff1@192.168.200.31 'echo \$SSH_CONNECTION' | grep -q '^10.8.0.2 '
        rc=\$?; wg-quick down wg0 >/dev/null 2>&1; exit \$rc"
}
t05_14() {
    dx fw-int grep -q 'TCP_DENIED/407' /var/log/squid/access.log \
        && dx fw-int grep -q 'TCP_MISS/200' /var/log/squid/access.log \
        && dx radius grep -q 'Auth:' /var/log/freeradius/radius.log \
        && dx arm1 grep -q 'Accepted password' /var/log/auth.log
}

# После up.sh провизия домена, ввод arm1 и запуск Squid идут в фоне: ждём их до 5 минут.
wait_ready() {
    local t0=$SECONDS
    until dx arm1 adcli testjoin --domain=gis.local >/dev/null 2>&1 \
        && dx fw-int sh -c 'ss -ltn | grep -q ":3128"' >/dev/null 2>&1 \
        && dx web curl -sk -m3 -o /dev/null https://localhost/ >/dev/null 2>&1; do
        if (( SECONDS - t0 > 300 )); then
            echo "Стенд не готов за 5 минут (домен/arm1, Squid или web)" >&2
            return 1
        fi
        sleep 5
    done
    echo "Стенд готов (ожидание ${SECONDS}s с запуска скрипта)"
}

wait_ready || exit 2
echo "Режим МЭ на старте: protect (принудительно)"
"$SCRIPT_DIR/mode.sh" protect >/dev/null

check 01.1  "ping attacker -> web (dmz) не проходит (protect)" t01_1
check 01.2  "ping attacker -> db (intra) не проходит (protect)" t01_2
check 01.3  "сайт открывается снаружи по публичному адресу (DNAT на web)" t01_3
check 01.4  "ssh на публичный адрес fw-ext закрыт" t01_4
check 01.5  "прямой доступ attacker -> dmz в обход DNAT закрыт" t01_5
check 01.6  "web -> db:5432 разрешён" t01_6
check 01.7  "web -> db:22 запрещён" t01_7
check 01.8  "ftp -> db:5432 запрещён (dmz -> intra только web -> db)" t01_8
check 01.9  "маршруты между зонами на роутерах" t01_9
check 01.10 "режим audit: ping attacker -> db проходит, затем возврат в protect" t01_10
check 01.11 "после возврата в protect ping attacker -> db снова закрыт" t01_11

check 02.1 "http -> 301 редирект на https" t02_1
check 02.2 "https news.php отдаёт данные из БД (200)" t02_2
check 02.3 "search.php отражает <script> (учебная XSS)" t02_3
check 02.4 "FTP: анонимный доступ запрещён" t02_4
check 02.5 "backup.sh: pg_dump и загрузка на ftp" t02_5
check 02.6 "webapp: SELECT из news разрешён" t02_6
check 02.7 "webapp: internal_notes и ALTER запрещены" t02_7
check 02.8 "pg_hba.conf отклоняет webapp с чужого адреса (МЭ выключен)" t02_8
check 02.9 "ftp переживает осиротевший процесс (init: true, vsftpd не PID 1)" t02_9

check 03.1 "Suricata: алерт XSS (sid 1000004)" t03_1
check 03.2 "Suricata: алерт SQLi OR 1=1 (sid 1000005)" t03_2
check 03.3 "Suricata: алерт SQLi UNION SELECT (sid 1000006)" t03_3
check 03.4 "Suricata: успешное HTTPS-подключение (sid 1000003)" t03_4
check 03.5 "Suricata: FTP USER (sid 1000008)" t03_5
check 03.6 "Suricata: ICMP снаружи (sid 1000001, audit)" t03_6
check 03.7 "Suricata: сканирование портов (sid 1000007, audit)" t03_7

check 04.1 "до туннеля client -> arm1:22 недоступен" t04_1
check 04.2 "после wg-quick up client -> arm1:22 доступен" t04_2
check 04.3 "через туннель db:5432 и dc:445 запрещены" t04_3
check 04.4 "client: handshake с сервером есть" t04_4
check 04.5 "vpn: handshake с клиентом есть" t04_5
check 04.6 "после wg-quick down доступ пропал" t04_6
check 04.7 "ключ-самозванец: handshake нет, доступа нет" t04_7

check 05.1  "dc: домен gis.local" t05_1
check 05.2  "arm1 введён в домен (adcli testjoin)" t05_2
check 05.3  "доменный вход archstaff1 на arm1 (группа workgroup)" t05_3
check 05.4  "sysadmin входит на arm1, Administrator нет (ad_access_filter)" t05_4
check 05.5  "faillock: блок после 3 неверных паролей, вход после сброса" t05_5
check 05.6  "парольная политика домена отклоняет слабый пароль" t05_6
check 05.7  "RADIUS: Accept для archstaff1, Reject для неверного пароля и guest" t05_7
check 05.8  "Squid: 407 без учётки и с неверной, 200 с верной" t05_8
check 05.9  "прямой выход arm1 в интернет в обход Squid закрыт" t05_9
check 05.10 "ACL /srv/archive: workgroup пишет, admin нет" t05_10
check 05.11 "AIDE: фиксирует правку отслеживаемого файла" t05_11
check 05.12 "ClamAV: EICAR найден, обычный файл чист" t05_12
check 05.13 "вход доменным пользователем через VPN (на arm1 виден 10.8.0.2)" t05_13
check 05.14 "журналы Squid, RADIUS и sshd содержат события" t05_14

{
    echo "# check-all.sh, $(date '+%Y-%m-%d %H:%M:%S')"
    printf '%s\n' "${RESULTS[@]}"
    echo "Итого: $((${#RESULTS[@]} - FAILS)) PASS, $FAILS FAIL из ${#RESULTS[@]}"
} > "$OUT"

echo "Итого: $((${#RESULTS[@]} - FAILS)) PASS, $FAILS FAIL из ${#RESULTS[@]} (таблица: results/06-checks.txt)"
[[ $FAILS -eq 0 ]]
