# Этап 05 — домен, АРМ, RADIUS + Squid, аналоги Secret Net

Этап выполнен в два захода. Часть А: контроллер домена dc на Samba AD, ввод arm1 в домен, вход
доменным пользователем, PAM (faillock, pwquality). Часть Б: FreeRADIUS, Squid с авторизацией через
RADIUS на fw-int, аналоги функций Secret Net на arm1 (ACL, AIDE, ClamAV, журнал входов), таблица
журналов, вход через VPN доменным пользователем.

## Цель
Поднять контроллер домена `gis.local` на открытом ПО вместо Windows Server, ввести АРМ
(Debian вместо Windows 10) в домен, настроить вход сотрудников доменными учётками, парольную
политику домена и блокировку учётки на АРМ после нескольких неудачных попыток входа.
Выпускать АРМ в интернет только через прокси после авторизации на RADIUS-сервере (примечание
схемы М2) и заменить функции Secret Net открытыми средствами.

## Что сделано (часть А)
- **dc** (intra .20): Samba 4.22.11 (Debian 13) в роли AD DC, домен `gis.local`, realm
  `GIS.LOCAL`, NetBIOS `GIS`, встроенный DNS Samba (`SAMBA_INTERNAL`). Провизия
  `samba-tool domain provision` выполняется один раз при первом старте; база
  (`/var/lib/samba`) и `smb.conf` (`/etc/samba`) лежат в named volume `gis_dc-lib` и `gis_dc-etc`.
- Пользователи и группы по документации ГИС: группа `Admin` (`sysadmin`, `secadmin`),
  группа `Workgroup` (`archhead`, `archstaff1`). Guest в домен не заводили, встроенная учётка
  Guest в Samba отключена (`userAccountControl: 66082`, флаг ACCOUNTDISABLE).
- Парольная политика домена: сложность включена, длина от 10, история 5, срок действия 90 дней,
  блокировка после 5 неудачных попыток на 15 минут.
- Пользователи, группы и политика применяются в entrypoint при каждом старте идемпотентно.
- **arm1** (intra .31): DNS на dc, ввод в домен через `adcli join` (учётка компьютера `ARM1$`,
  `/etc/krb5.keytab`), SSSD (провайдер `ad`) для пользователей и групп, Kerberos при входе.
  Войти на АРМ могут только члены доменных групп Admin и Workgroup (`ad_access_filter`).
- PAM на arm1: `pam_faillock` (3 неудачных попытки за 15 минут → блокировка на 5 минут),
  `pam_pwquality` (длина от 10, заглавные, строчные, цифры, без имени пользователя, словарь),
  `pam_mkhomedir` (домашний каталог доменного пользователя создаётся при первом входе).
- sshd на arm1 остался (нужен этапу 04), теперь через него входят и доменные пользователи.
  Локальная учётка `armuser` с этапа 04 сохранена.
- Новые учебные пароли `DC_ADMIN_PASSWORD` и `DOMAIN_USER_PASSWORD` в `stand/secrets/stand.env`,
  `up.sh` дописывает отсутствующие переменные в уже существующий файл.

## Что сделано (часть Б)
- **radius** (transit .5): FreeRADIUS 3.2.7. Единственный внешний клиент (NAS) — fw-int
  (192.168.50.4, общий секрет `RADIUS_SECRET`). Пользователи в файле users
  (`mods-config/files/authorize`): archstaff1, archhead, sysadmin, secadmin с паролем
  `PROXY_USER_PASSWORD`, guest заведён явно с отказом (`Auth-Type := Reject`). Каждая попытка
  входа пишется в `/var/log/freeradius/radius.log` (`auth = yes`, без паролей).
- **fw-int**: Squid 6.13 слушает только 192.168.200.1:3128 (intra). Basic-авторизация, логин и
  пароль проверяет хелпер `basic_radius_auth` на radius. Доступ разрешён только из intra и только
  после успешной авторизации. Прямой выход из intra наружу, как и раньше, режется в forward
  (`c_int_fwd_drop`), наружу ходит сам fw-int (правило `c_ext_fwint_out` на fw-ext с этапа 01).
- В nftables fw-int (режим protect) добавлена цепочка input с политикой drop: к самому fw-int
  можно только на 3128 из intra и ICMP, ответы RADIUS приходят как established.
- **inet** (ext .80): готовый с этапа 01 `python3 -m http.server`, цель проверки выхода.
- **arm1**, аналоги Secret Net: каталог отдела `/srv/archive` с POSIX ACL только для группы
  Workgroup; AIDE (`/etc/aide/aide-gis.conf`) с эталонной базой, которая создаётся при старте;
  ClamAV 1.4.3 с локальной сигнатурой EICAR; rsyslog, журнал входов в `/var/log/auth.log`.
  auditd в контейнере не запускается (см. отступления).
- **dc**: включён журнал аутентификации Samba (`log level = 1 auth_audit:3`).
- **client**: добавлен sshpass, клиент через WireGuard входит на arm1 доменной учёткой.
- Новые учебные значения `RADIUS_SECRET` и `PROXY_USER_PASSWORD` в `stand/secrets/stand.env`.

## Конфигурация (ключевые фрагменты)
Полные файлы: `stand/nodes/dc/{Dockerfile,entrypoint.sh}`, `stand/nodes/arm1/{Dockerfile,entrypoint.sh,krb5.conf,sssd.conf,faillock.conf,pwquality.conf,pam/common-*}`, `stand/docker-compose.yml` (сервисы dc, arm1, volumes).

Провизия домена (`stand/nodes/dc/entrypoint.sh`):
```
samba-tool domain provision --server-role=dc --use-rfc2307 --dns-backend=SAMBA_INTERNAL \
    --realm=GIS.LOCAL --domain=GIS --host-name=dc --host-ip=192.168.200.20 \
    --adminpass="$DC_ADMIN_PASSWORD" \
    --option="acl_xattr:security_acl_name = user.NTACL" \
    --option="interfaces = lo eth0" --option="bind interfaces only = yes"
```

Парольная политика:
```
samba-tool domain passwordsettings set --complexity=on --store-plaintext=off --history-length=5 \
    --min-pwd-length=10 --min-pwd-age=0 --max-pwd-age=90 \
    --account-lockout-threshold=5 --account-lockout-duration=15 --reset-account-lockout-after=15
```

Ввод arm1 в домен (`stand/nodes/arm1/entrypoint.sh`, выполняется, если в keytab нет `ARM1$`):
```
printf '%s' "$DC_ADMIN_PASSWORD" | adcli join --domain=gis.local \
    --domain-controller=dc.gis.local --host-fqdn=arm1.gis.local \
    --login-user=Administrator --stdin-password
```

SSSD (`stand/nodes/arm1/sssd.conf`, главное):
```
id_provider = ad
access_provider = ad
ldap_id_mapping = true
use_fully_qualified_names = false
fallback_homedir = /home/%u
ad_gpo_access_control = permissive
ad_access_filter = (|(memberOf=CN=Admin,CN=Users,DC=gis,DC=local)(memberOf=CN=Workgroup,CN=Users,DC=gis,DC=local))
```

PAM, `common-auth`:
```
auth  required                    pam_faillock.so preauth
auth  [success=3 default=ignore]  pam_unix.so nullok
auth  [success=2 default=ignore]  pam_sss.so use_first_pass
auth  [default=die]               pam_faillock.so authfail
auth  requisite                   pam_deny.so
auth  required                    pam_permit.so
```
PAM, `common-account`:
```
account  required  pam_faillock.so
account  [success=1 new_authtok_reqd=done default=ignore]  pam_unix.so
account  requisite pam_deny.so
account  required  pam_permit.so
account  [default=bad success=ok user_unknown=ignore]  pam_sss.so
```
`/etc/security/faillock.conf`: `deny = 3`, `fail_interval = 900`, `unlock_time = 300`, `audit`.
`/etc/security/pwquality.conf`: `minlen = 10`, `dcredit = ucredit = lcredit = -1`, `difok = 3`,
`maxrepeat = 3`, `dictcheck = 1`, `usercheck = 1`, `enforce_for_root`.

Как это работает при входе по ssh: preauth проверяет, не заблокирован ли пользователь; пароль
проверяется локально (`pam_unix`), а если пользователь доменный, то через SSSD на контроллере
домена по Kerberos (`pam_sss`). Неудача записывается в `/var/run/faillock/<имя>`. В фазе account
SSSD проверяет `ad_access_filter`, успешный вход обнуляет счётчик faillock.

### Часть Б
Полные файлы: `stand/nodes/radius/{Dockerfile,entrypoint.sh}`, `stand/nodes/fw-int/{Dockerfile,entrypoint.sh,squid.conf,nft/fw-int-*.nft}`, `stand/nodes/arm1/{Dockerfile,entrypoint.sh,aide-gis.conf,gis-eicar.ndb}`, `stand/nodes/dc/entrypoint.sh`.

FreeRADIUS, клиент fw-int (`clients.conf`, секрет подставляет entrypoint из `stand.env`):
```
client fw-int {
	ipv4addr  = 192.168.50.4
	secret    = ***
	shortname = fw-int
	require_message_authenticator = no
	limit_proxy_state = no
}
```
Пользователи (`mods-config/files/authorize`):
```
archstaff1	Cleartext-Password := "***"
archhead	Cleartext-Password := "***"
sysadmin	Cleartext-Password := "***"
secadmin	Cleartext-Password := "***"
guest	Auth-Type := Reject
	Reply-Message := "Guest: доступ в интернет запрещён"
```

Squid (`stand/nodes/fw-int/squid.conf`, главное); `/etc/squid/radius.conf` с `server 192.168.50.5`,
`secret`, `identifier fw-int` создаёт entrypoint, права `640 root:proxy`:
```
http_port 192.168.200.1:3128
max_filedescriptors 4096
auth_param basic program /usr/lib/squid/basic_radius_auth -f /etc/squid/radius.conf -t 5
auth_param basic realm GIS proxy: login RADIUS
acl intra src 192.168.200.0/24
acl radius_users proxy_auth REQUIRED
http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports
http_access deny !intra
http_access allow intra radius_users
http_access deny all
access_log daemon:/var/log/squid/access.log squid
```

nftables fw-int, режим protect, новая цепочка input (в audit — `policy accept`):
```
chain input {
    type filter hook input priority 0; policy drop;
    iif lo accept
    ct state established,related accept
    ip protocol icmp accept
    ip saddr 192.168.200.0/24 ip daddr 192.168.200.1 tcp dport 3128 counter name c_int_proxy_in accept
    counter name c_int_in_drop drop
}
```

arm1, разграничение доступа (entrypoint, после того как SSSD отдал группу workgroup):
```
install -d -o root -g root -m 0770 /srv/archive
setfacl -m g:workgroup:rwx,d:g:workgroup:rwx,d:g::---,d:o::---,m::rwx /srv/archive
```
`d:g::---` нужен потому, что основная группа доменных пользователей `domain users`: без него
новый файл получал бы права группы-владельца для всех доменных пользователей.

AIDE (`stand/nodes/arm1/aide-gis.conf`): правило `GIS = p+u+g+s+m+sha256+acl` на `/etc/passwd`,
`/etc/group`, `/etc/ssh/sshd_config`, `/etc/krb5.conf`, `/etc/pam.d`, `/etc/security`, `/etc/sssd`,
`/usr/local/bin`. База `--init` в конце entrypoint, проверка `aide -c /etc/aide/aide-gis.conf --check`.

ClamAV, локальная сигнатура (`/var/lib/clamav/gis-eicar.ndb`, формат ndb: имя, тип файла 0 = любой,
смещение * = где угодно, hex строки `EICAR-STANDARD-ANTIVIRUS-TEST-FILE`):
```
GIS.Test.EICAR:0:*:45494341522d5354414e444152442d414e544956495255532d544553542d46494c45
```

Samba, журнал аутентификации (entrypoint dc, при каждом старте): `log level = 1 auth_audit:3` в `[global]`.

## Проверка функционирования

### Проверка 1 — контроллер домена работает
- Команда: `docker exec gis-dc samba-tool domain info 127.0.0.1`
- Ожидание: домен gis.local, DC dc.gis.local.
- Получили: `Forest: gis.local`, `Domain: gis.local`, `Netbios domain: GIS`, `DC name: dc.gis.local`.
- Скрин: screens/05-dc-domain-info.png
- Итог: PASS

### Проверка 2 — DNS домена (SRV-записи) с arm1
- Команда: `docker exec gis-arm1 bash -c 'cat /etc/resolv.conf; host -t SRV _ldap._tcp.gis.local; host -t SRV _kerberos._udp.gis.local; host dc.gis.local'`
- Ожидание: arm1 использует dc как DNS, SRV-записи LDAP и Kerberos указывают на dc.gis.local.
- Получили: `nameserver 192.168.200.20`, `_ldap._tcp.gis.local has SRV record 0 100 389 dc.gis.local.`, `_kerberos._udp.gis.local has SRV record 0 100 88 dc.gis.local.`, `dc.gis.local has address 192.168.200.20`.
- Скрин: screens/05-dc-dns-srv.png
- Итог: PASS

### Проверка 3 — пользователи и группы домена
- Команда: `docker exec gis-dc bash -c 'samba-tool user list | sort; samba-tool group listmembers Admin; samba-tool group listmembers Workgroup'`
- Ожидание: sysadmin, secadmin в Admin; archhead, archstaff1 в Workgroup.
- Получили: пользователи `Administrator, Guest, archhead, archstaff1, krbtgt, secadmin, sysadmin` (Administrator, Guest, krbtgt встроенные); Admin: `secadmin, sysadmin`; Workgroup: `archstaff1, archhead`.
- Скрин: screens/05-dc-users-groups.png
- Итог: PASS

### Проверка 4 — парольная политика домена
- Команда: `docker exec gis-dc samba-tool domain passwordsettings show`, затем `docker exec gis-dc samba-tool user create testweak qwerty12`
- Ожидание: политика как задали; пользователь со слабым паролем не создаётся.
- Получили: `Password complexity: on`, `Minimum password length: 10`, `Password history length: 5`, `Maximum password age (days): 90`, `Account lockout threshold (attempts): 5`, `Account lockout duration (mins): 15`. Создание testweak: `Constraint violation - check_password_restrictions: the password is too short. It should be equal to or longer than 10 characters!`
- Скрин: screens/05-dc-passwordsettings.png, screens/05-dc-weak-password.png
- Итог: PASS

### Проверка 5 — arm1 введён в домен
- Команда: `docker exec gis-arm1 bash -c 'adcli testjoin --domain=gis.local; klist -k /etc/krb5.keytab | ...'; docker exec gis-dc samba-tool computer list`
- Ожидание: проверка ввода успешна, в keytab ключи ARM1$ и host/arm1.gis.local, на dc есть учётка компьютера ARM1$.
- Получили: `Sucessfully validated join to domain gis.local` (опечатка в самом adcli), в keytab `ARM1$@GIS.LOCAL`, `host/ARM1@GIS.LOCAL`, `host/arm1.gis.local@GIS.LOCAL`, `RestrictedKrbHost/...`; на dc `ARM1$` и `DC$`. Дополнительно SSSD сам зарегистрировал arm1 в DNS домена: `host arm1.gis.local` → `192.168.200.31`.
- Скрин: screens/05-arm1-join.png
- Итог: PASS

### Проверка 6 — доменные пользователи видны на arm1
- Команда: `docker exec gis-arm1 bash -c 'getent passwd archstaff1 archhead sysadmin secadmin; id archstaff1; id sysadmin; getent group workgroup admin'`
- Ожидание: учётки и группы приходят из домена через SSSD (локально их нет).
- Получили: `archstaff1:*:1357001108:1357000513:Сотрудник архива:/home/archstaff1:/bin/bash`, `uid=1357001108(archstaff1) gid=1357000513(domain users) groups=1357000513(domain users),1357001104(workgroup)`, `workgroup:*:1357001104:archhead,archstaff1`, `admin:*:1357001103:secadmin,sysadmin`.
- Скрин: screens/05-arm1-getent.png
- Итог: PASS

### Проверка 7 — вход доменным пользователем
- Команда: `docker exec gis-arm1 bash -c 'sshpass -p "$DOMAIN_USER_PASSWORD" ssh ... archstaff1@localhost "id; hostname -f; pwd; klist | head -5"'`
- Ожидание: вход по паролю домена, создан домашний каталог, выдан билет Kerberos.
- Получили: `uid=1357001108(archstaff1) ... groups=...,1357001104(workgroup)`, `arm1.gis.local`, `/home/archstaff1`, `Default principal: archstaff1@GIS.LOCAL`, билет `krbtgt/GIS.LOCAL@GIS.LOCAL` на 10 часов.
- Скрин: screens/05-arm1-domain-login.png
- Итог: PASS

### Проверка 8 — на АРМ пускают только группы Admin и Workgroup
- Команда: вход по ssh на arm1 под `sysadmin` (группа Admin) и под `Administrator` (администратор домена, но не в Admin/Workgroup), затем строки лога sshd.
- Ожидание: sysadmin входит, Administrator получает отказ на этапе проверки учётки (account), хотя пароль верный.
- Получили: `sysadmin: код ssh 0`, `Administrator: код ssh 255`; в логе sshd `Accepted password for sysadmin from ::1`, `Access denied for user Administrator by PAM account configuration [preauth]`.
- Скрин: screens/05-arm1-access-filter.png
- Итог: PASS

### Проверка 9 — блокировка после неудачных попыток (pam_faillock)
- Команда: три входа `archstaff1` с неверным паролем, `faillock --user archstaff1`, затем вход с верным паролем; после этого `faillock --user archstaff1 --reset` и снова вход с верным паролем.
- Ожидание: после 3 неудач учётка заблокирована на arm1, даже верный пароль не пускает; после сброса вход работает.
- Получили: попытки 1-3 `Permission denied (publickey,password)`, код 255; faillock показывает три записи `RHOST ::1 V` (09:35:06, 09:35:10, 09:35:13); попытка 4 с верным паролем тоже `Permission denied`, код 255. После сброса таблица faillock пустая, `вход выполнен: archstaff1@arm1`, код 0. В логе sshd четыре `Failed password for archstaff1` подряд, затем `Accepted password`.
- Скрин: screens/05-arm1-faillock-lock.png, screens/05-arm1-faillock-reset.png, screens/05-arm1-sshd-log.png
- Итог: PASS

### Проверка 10 — сложность паролей на АРМ (pam_pwquality)
- Команда: `echo "armuser:<пароль>" | chpasswd` для паролей `qwerty123`, `archive2026`, `Arm1armuser`
- Ожидание: все три отклонены, пароль armuser не меняется.
- Получили: для первых двух `BAD PASSWORD: The password contains less than 1 uppercase letters`, для третьего `BAD PASSWORD: The password contains the user name in some form`, итог `pam_chauthtok() failed`. Вход armuser со старым паролем после этого работает.
- Скрин: screens/05-arm1-pwquality.png
- Итог: PASS

### Проверка 11 — стенд с нуля
- Команда: `docker compose down -v` (проект gis), `stand/scripts/up.sh`
- Ожидание: dc сам провизирует домен на пустом volume, arm1 дожидается dc и входит в домен без ручных действий.
- Получили: все 13 контейнеров `Up`, в логе arm1 `Created computer account: CN=ARM1,CN=Computers,DC=gis,DC=local`, доменный вход archstaff1 работает, сайт снаружи отвечает 200. Скрины проверок 1-10 сняты именно на этом свежем стенде.
- Итог: PASS

Проверки 12-24 (часть Б) сняты на стенде, поднятом 30.10 заново через `docker compose down -v` и `up.sh`: домен провизировался, arm1 вошёл в домен, ACL и база AIDE созданы без ручных действий. После этого dc один раз пересобрали (включили `auth_audit`).

### Проверка 12 — настройки RADIUS-сервера
- Команда: `docker exec gis-radius ...` вывод блоков `gis-begin/gis-end` из `clients.conf` и `mods-config/files/authorize` (секрет и пароли заменены на `***` при выводе).
- Ожидание: единственный внешний клиент fw-int, четыре учётки и guest с отказом.
- Получили: `client fw-int { ipv4addr = 192.168.50.4 ... }`, учётки archstaff1, archhead, sysadmin, secadmin, `guest Auth-Type := Reject`.
- Скрин: screens/05-radius-config.png
- Итог: PASS

### Проверка 13 — radtest с верными и неверными данными
- Команда: с fw-int (настоящий клиент RADIUS) `radtest -t pap <логин> <пароль> 192.168.50.5 0 <секрет>` для четырёх случаев.
- Ожидание: верные данные → Access-Accept; неверный пароль → Access-Reject; guest → Access-Reject с сообщением; неверный общий секрет → сервер не отвечает.
- Получили: `Received Access-Accept Id 112 from 192.168.50.5:1812`; `Received Access-Reject Id 239`; для guest `Received Access-Reject Id 69` и `Reply-Message = "Guest: доступ в интернет запрещён"`; с неверным секретом `No reply from server for ID 38` (FreeRADIUS отбрасывает пакет с неверной подписью).
- Скрин: screens/05-radius-radtest.png
- Итог: PASS

### Проверка 14 — выход в интернет через Squid только после авторизации на RADIUS
- Команда: на arm1 `curl -x http://192.168.200.1:3128 http://198.51.100.80/` без учётки, с неверным паролем (`archstaff1:WrongPass123`), под guest и с верной учёткой.
- Ожидание: 407, 407, 407, 200.
- Получили: `HTTP 407`, `HTTP 407`, `HTTP 407`, `<h1>«Сайт в интернете» — для проверки выхода АРМ (этап 05)</h1>`, `HTTP 200`.
- Скрин: screens/05-squid-auth.png
- Итог: PASS

### Проверка 15 — прямой выход из intra без прокси закрыт
- Команда: `docker exec gis-arm1 curl -m 5 http://198.51.100.80/`, затем `nft list counter inet filter c_int_fwd_drop` на fw-int.
- Ожидание: соединение не устанавливается, счётчик drop на fw-int растёт.
- Получили: `HTTP 000`, код curl 28 (таймаут); `c_int_fwd_drop packets 7 bytes 468`.
- Скрин: screens/05-squid-direct.png
- Итог: PASS

### Проверка 16 — журналы Squid и FreeRADIUS
- Команда: `docker exec gis-fw-int tail -5 /var/log/squid/access.log`; `docker exec gis-radius grep "Auth:" /var/log/freeradius/radius.log | tail -6`.
- Ожидание: в Squid видны отказы 407 и успешный запрос с логином; в FreeRADIUS те же попытки от клиента fw-int.
- Получили: Squid `TCP_DENIED/407 ... GET http://198.51.100.80/ -` (без учётки), `TCP_DENIED/407 ... archstaff1`, `TCP_DENIED/407 ... guest`, `TCP_MISS/200 514 GET http://198.51.100.80/ archstaff1 HIER_DIRECT/198.51.100.80`. FreeRADIUS: `Login incorrect (pap: Cleartext password does not match "known good" password): [archstaff1] (from client fw-int port 111)`, `Login incorrect: [guest] (from client fw-int port 111)`, `Login OK: [archstaff1] (from client fw-int port 111)`. Порт 111 подставляет хелпер Squid, порт 0 — radtest из проверки 13.
- Скрин: screens/05-squid-log.png, screens/05-radius-log.png
- Итог: PASS

### Проверка 17 — к самому fw-int открыт только прокси из intra
- Команда: `docker exec gis-fw-int bash -c 'nft list chain inet filter input; ss -ltn | grep 3128'`
- Ожидание: политика input drop, разрешён только tcp 3128 из 192.168.200.0/24; Squid слушает только адрес в intra.
- Получили: `policy drop`, правило `ip saddr 192.168.200.0/24 ip daddr 192.168.200.1 tcp dport 3128 ... accept`, `LISTEN ... 192.168.200.1:3128`.
- Скрин: screens/05-fwint-input.png
- Итог: PASS

### Проверка 18 — разграничение доступа к каталогу отдела (ACL)
- Команда: `getfacl -p /srv/archive`, затем по ssh на arm1 под archstaff1, archhead (Workgroup) и sysadmin (Admin) запись файла в `/srv/archive` и `ls`.
- Ожидание: члены Workgroup пишут и читают, sysadmin получает отказ.
- Получили: `group:workgroup:rwx`, `default:group::---`, `other::---`. archstaff1 и archhead: `запись OK`. sysadmin: `/srv/archive/sysadmin.txt: Permission denied`, `ls: cannot open directory '/srv/archive': Permission denied`. Файлы `-rw-rw----+ archhead`, `-rw-rw----+ archstaff1`.
- Скрин: screens/05-acl.png
- Итог: PASS

### Проверка 19 — контроль целостности (AIDE)
- Команда: `aide -c /etc/aide/aide-gis.conf --check`; затем `echo "PermitRootLogin yes" >> /etc/ssh/sshd_config` и снова `--check`. После проверки файл вернули из копии и пересоздали базу.
- Ожидание: до изменения расхождений нет; после изменения AIDE показывает изменённый файл.
- Получили: до `AIDE found NO differences between database and filesystem. Looks okay!!`, 45 записей. После `AIDE found differences ... Changed entries: 1`, `f > ... m   H.     : /etc/ssh/sshd_config`, `Size: 3424 | 3444`, разные SHA256, код возврата aide 4 (есть изменённые файлы).
- Скрин: screens/05-aide-ok.png, screens/05-aide-detect.png
- Итог: PASS

### Проверка 20 — антивирус (ClamAV, EICAR)
- Команда: создать `/srv/eicar.com` со стандартной тестовой строкой EICAR и обычный `doc.txt`, `clamscan eicar.com doc.txt`.
- Ожидание: EICAR найден, обычный файл чистый.
- Получили: `/srv/eicar.com: GIS.Test.EICAR.UNOFFICIAL FOUND`, `/srv/doc.txt: OK`, `Known viruses: 1`, `Infected files: 1`, код clamscan 1. Суффикс UNOFFICIAL ClamAV добавляет ко всем сигнатурам не из официальной базы.
- Скрин: screens/05-clamav-eicar.png
- Итог: PASS

### Проверка 21 — аудит (auditd) в контейнере
- Команда: `timeout 5 auditd -f; auditctl -s` на arm1.
- Ожидание: показать, запускается ли auditd без дополнительных прав.
- Получили: `You must be root or have capabilities to run this program.`, `The audit daemon is exiting.`, `auditctl`: `You must be root to run this program.` (процесс root, но без CAP_AUDIT_CONTROL).
- Скрин: screens/05-auditd.png
- Итог: ограничение зафиксировано, регистрация входов сделана через rsyslog (проверка 22).

### Проверка 22 — журнал входов на arm1
- Команда: неверный пароль archhead и попытка входа Administrator, затем `grep -E "Accepted|Failed|session (opened|closed)|faillock|Access denied" /var/log/auth.log | tail -8`.
- Ожидание: в журнале видны успешные входы, неудачи и отказ по фильтру доступа.
- Получили: `Accepted password for sysadmin from ::1`, `session opened for user sysadmin(uid=1876601105)`, `session closed for user sysadmin`, `Failed password for archhead from ::1`, `pam_sss(sshd:account): Access denied for user Administrator: 6 (Permission denied)`, `fatal: Access denied for user Administrator by PAM account configuration [preauth]`.
- Скрин: screens/05-arm1-authlog.png
- Итог: PASS

### Проверка 23 — вход через VPN доменным пользователем (совместно с этапом 04)
- Команда: на client `wg-quick up wg0`, `wg show`, `sshpass ... ssh archstaff1@192.168.200.31 "id; hostname -f; klist; echo $SSH_CONNECTION"`, `wg-quick down wg0`; на arm1 строка из auth.log.
- Ожидание: туннель поднят, вход доменной учёткой, на arm1 виден адрес клиента в туннеле.
- Получили: `endpoint: 198.51.100.1:51820`, `latest handshake: Now`; `uid=1876601108(archstaff1) ... groups=...,1876601104(workgroup)`, `arm1.gis.local`, `Default principal: archstaff1@GIS.LOCAL`, `SSH_CONNECTION=10.8.0.2 45394 192.168.200.31 22`, код ssh 0; в auth.log `Accepted password for archstaff1 from 10.8.0.2 port 45394 ssh2`.
- Скрин: screens/05-vpn-domain-ssh.png
- Итог: PASS

### Проверка 24 — минимальное логирование по узлам
- Команда: по одной последней записи из каждого журнала (см. таблицу ниже).
- Ожидание: на каждом узле есть журнал своих событий.
- Получили: примеры строк в таблице ниже.
- Скрин: screens/05-logs-examples.png
- Итог: PASS

## Журналы событий (примечание 8 схемы М2)
Журналы лежат внутри контейнеров, кроме Suricata (смонтирован на хост). Смотреть: `docker exec gis-<узел> tail <путь>`.

| Узел | Какие события | Где журнал | Пример записи |
|---|---|---|---|
| web | HTTP-запросы к сайту, ошибки Apache | `/var/log/apache2/gis-access.log`, `gis-error.log` | `198.51.100.66 - - [30/Oct/2026:09:51:16 +0000] "GET / HTTP/1.1" 200 3864 "-" "curl/8.14.1"` |
| gw-dmz | алерты IDS Suricata | `stand/logs/gw-dmz/fast.log`, `eve.json` | `[1:1000004:1] Vozmozhnaya XSS-ataka: <script> v HTTP-zaprose ... 198.51.100.66:34346 -> 192.168.100.10:80` |
| fw-ext, gw-dmz, fw-int | отброшенные и разрешённые пакеты (именованные счётчики nft) | `nft list counters` | `c_ext_fwd_drop packets 1 bytes 58`, `c_int_fwd_drop packets 7 bytes 468` |
| fw-int | запросы через прокси с логином и кодом ответа | `/var/log/squid/access.log` | `192.168.200.31 TCP_MISS/200 514 GET http://198.51.100.80/ archstaff1 HIER_DIRECT/198.51.100.80` |
| radius | попытки аутентификации (успех/отказ, клиент) | `/var/log/freeradius/radius.log` | `Auth: (8) Login OK: [archstaff1] (from client fw-int port 111)` |
| dc | проверки пароля и выдача билетов Kerberos | `/var/log/samba/log.samba` | `Auth: [Kerberos KDC,ENC-TS Pre-authentication] ... [archstaff1...] ... status [NT_STATUS_OK] ... remote host [ipv4:192.168.200.31:...]` |
| arm1 | входы и выходы по ssh, неудачи, отказы PAM | `/var/log/auth.log` | `Accepted password for archstaff1 from 10.8.0.2 port 45394 ssh2` |
| ftp | сеансы и команды FTP | `/var/log/vsftpd/vsftpd.log` | `[ftpbackup] FTP response: Client "192.168.200.10", "221 Goodbye."` |
| db | запуск и ошибки PostgreSQL | `docker logs gis-db` | `LOG:  database system is ready to accept connections` |
| vpn | состояние туннеля (последний handshake, объём) | `wg show` на vpn | см. этап 04, screens/04-wg-show-vpn.png |

## Функции Secret Net и чем заменили

| Функция Secret Net | Чем заменили | Проверка | Результат |
|---|---|---|---|
| Идентификация и аутентификация, парольная политика | Samba AD (политика домена), SSSD+Kerberos на arm1, pam_pwquality | проверки 4, 7, 10 | PASS |
| Блокировка после неудачных попыток | pam_faillock на arm1 (3 попытки), блокировка в домене (5 попыток) | проверка 9 | PASS |
| Разграничение доступа к АРМ | `ad_access_filter` SSSD: только Admin и Workgroup | проверка 8 | PASS |
| Разграничение доступа к ресурсам (дискреционное) | POSIX ACL на `/srv/archive` для Workgroup | проверка 18 | PASS |
| Контроль целостности | AIDE (хеш SHA-256, права, владелец, ACL) | проверка 19 | PASS |
| Антивирусная защита | ClamAV 1.4.3, локальная сигнатура EICAR | проверка 20 | PASS |
| Регистрация событий | rsyslog (auth.log), журнал Samba auth_audit; auditd не работает в контейнере | проверки 21, 22, 24 | PASS с ограничением |
| Двухфакторная аутентификация (ключ + пароль) | не моделировали | — | не сделано |

## Отступления от схемы и причины
1. Вместо Windows Server DC используется Samba AD DC, вместо Windows 10 АРМ Debian-клиент с SSSD (решение группы, см. `prompts/00-context.md`).
2. NT ACL на sysvol хранятся в xattr `user.NTACL`, а не в `security.NTACL` (опция `acl_xattr:security_acl_name`). Для `security.*` контейнеру нужен `CAP_SYS_ADMIN`, его не давали, `--privileged` тоже не нужен. На работу домена это не влияет, отличие только в месте хранения ACL. Запасной вариант (MIT Kerberos + OpenLDAP) не понадобился.
3. Атрибуты RFC2307 (uidNumber/gidNumber) пользователям не заполняли, SSSD вычисляет UID/GID из SID (`ldap_id_mapping = true`). Из-за этого номера UID зависят от SID домена и меняются после повторной провизии с нуля (при первом запуске были 481001108, на свежем стенде 1357001108).
4. Групповые политики не настраивали, `ad_gpo_access_control = permissive` (GPO не мешают входу). Доступ к АРМ ограничен фильтром SSSD по группам Admin и Workgroup.
5. В `/etc/pam.d/sshd` на arm1 `pam_loginuid` переведён из `required` в `optional`: без `CAP_AUDIT_CONTROL` контейнер не может записать loginuid, и сессия sshd рвалась бы.
6. Двухфакторную аутентификацию (электронный ключ + пароль из документации ГИС) не моделировали, только пароль.
7. Блокировка работает на двух уровнях: на arm1 faillock блокирует после 3 попыток, в домене после 5. Порог на АРМ ниже, поэтому подбор пароля через arm1 упирается в faillock раньше, чем учётка блокируется во всём домене (после неудачных попыток и успешного входа в домене `badPwdCount: 0`).
8. RADIUS проверяет пользователей по своему файлу users, а не по паролям домена. Пароль для прокси (`PROXY_USER_PASSWORD`) отдельный от доменного. Привязку FreeRADIUS к Samba через `ntlm_auth` не делали: radius стоит в transit, для неё нужен winbind на radius, ввод его в домен и правила fw-int для LDAP/Kerberos/SMB из transit в intra. Методичка допускает файл users как основной вариант.
9. Для клиента fw-int на FreeRADIUS явно выключено требование Message-Authenticator (`require_message_authenticator = no`, `limit_proxy_state = no`), то есть защита от атаки BlastRADIUS (CVE-2024-3596) для этого клиента не действует. Причина: хелпер Squid `basic_radius_auth` (Squid 6.13) этот атрибут не отправляет (проверили tcpdump: в Access-Request только NAS-Port, NAS-Port-Type, NAS-Identifier и обычные User-Name/User-Password). Риск ограничен тем, что fw-int и radius в одном сегменте transit, куда снаружи доступа нет.
10. ClamAV работает с одной локальной сигнатурой EICAR (`gis-eicar.ndb`), а не с официальной базой. Стенд без выхода в интернет, а официальная база (main/daily/bytecode) около 200 МБ и обновляется через freshclam с CDN ClamAV. Механизм проверки тот же, что и с полной базой, отличается только набор сигнатур.
11. auditd в контейнере не работает: для него нужна capability `CAP_AUDIT_CONTROL`, а подсистема аудита ядра не изолирована пространствами имён, то есть правила аудита из контейнера легли бы на ядро хоста. Хост по правилам проекта не трогаем, поэтому capability не давали. Регистрацию входов и действий PAM ведёт rsyslog (`/var/log/auth.log`), проверки пароля на контроллере домена пишет Samba (`auth_audit`). Аудит команд пользователей (аналог журнала действий Secret Net) не моделировали.
12. С появлением rsyslog sshd на arm1 запускается без `-e`, поэтому его записи теперь в `/var/log/auth.log`, а не в `docker logs gis-arm1` (скрин 05-arm1-sshd-log части А снят ещё по `docker logs`).
13. Журналы Squid и FreeRADIUS оставлены внутри контейнеров, на хост не смонтированы: эти службы пишут журнал от своих пользователей (proxy, freerad), и bind-mount пришлось бы отдавать им во владение, после чего папку на хосте нельзя удалить без sudo.
14. GUI АРМ (Xfce + noVNC, п. 8 этапа, опционально) не делали.

## Проблемы и как решили
1. **Администратор домена входил на АРМ, хотя не состоит в Admin/Workgroup.** В первой версии `common-account` pam_unix и pam_sss стояли как альтернативы. pam_unix в фазе account возвращает success для любого пользователя, которого видит NSS (в том числе доменного через SSSD), поэтому до pam_sss и `ad_access_filter` дело не доходило. Сделали как в штатном профиле Debian для SSSD: pam_sss отдельной обязательной строкой после pam_unix (`[default=bad success=ok user_unknown=ignore]`). После этого `Access denied for user Administrator by PAM account configuration`.
2. **`chpasswd` в entrypoint arm1 перестал задавать пароль armuser.** После включения pwquality chpasswd идёт через PAM, а словаря cracklib в образе не было: `BAD PASSWORD: The password fails the dictionary check - error loading dictionary`. Добавили пакет `cracklib-runtime`, словарная проверка заработала.
3. **Повторный ввод в домен после пересоздания контейнера.** Keytab живёт в контейнере и теряется при пересоздании, а учётка ARM1$ на dc остаётся. Проверили: `adcli join` находит существующую учётку (`Found computer account for ARM1$`) и просто обновляет пароль и keytab, ошибки нет.
4. **Ложное срабатывание `set -e` в entrypoint dc (найдено при написании).** Проверка членства в группе через `samba-tool ... | grep -q` под `pipefail` могла упасть из-за SIGPIPE. Вывод сначала сохраняется в переменную, потом grep.
5. Пароль администратора передаётся `samba-tool domain provision` и `samba-tool user create` аргументом (так устроены эти команды), он виден в списке процессов на время провизии. Для учебного стенда допустимо, на arm1 пароль передаётся adcli через stdin.
6. **Squid сразу падал при старте:** `FATAL: xcalloc: Unable to allocate 1073741816 blocks of 432 bytes!`. Docker даёт контейнеру лимит открытых файлов около 10^9, Squid берёт его как размер таблицы дескрипторов. Ограничили `max_filedescriptors 4096` в `squid.conf`.
7. **Squid отвечал 407 даже на верную учётку**, хотя radtest с той же учёткой получал Access-Accept. В `cache.log` хелпера `basic_radius_auth: No response from RADIUS server`, в `radius.log` `It looks like the client has been updated to protect from the BlastRADIUS attack. Please set "require_message_authenticator = true" for client fw-int`. FreeRADIUS 3.2.7 по умолчанию работает в режиме `auto`: увидев от fw-int первый запрос с Message-Authenticator (его шлёт radtest), он начинает требовать этот атрибут от всех запросов клиента и молча отбрасывает запросы хелпера Squid, который его не шлёт. tcpdump подтвердил, что атрибута в запросах Squid нет. Явно задали для fw-int `require_message_authenticator = no` (см. отступление 9). Попутно поймали, что `docker compose up --force-recreate` без пересборки образа не подхватывает новый entrypoint (он копируется в образ), пересобирали `docker compose build radius`.
8. **Новые файлы в `/srv/archive` получали доступ для всех доменных пользователей через группу-владельца.** Основная группа у доменных пользователей `domain users`, и с первой версией ACL файл archstaff1 создавался с `group::rwx #effective:rw-` для неё. Пока каталог закрыт, прочитать его не мог никто посторонний, но при переносе файла это была бы дыра. Добавили default-ACL `d:g::---`.
9. **В журнале Samba не было событий входа.** По умолчанию `log level = 0`, в `log.samba` только сообщения о запуске. Включили `auth_audit:3`. smb.conf лежит в volume и создаётся только при провизии, поэтому строку правит entrypoint при каждом старте.

