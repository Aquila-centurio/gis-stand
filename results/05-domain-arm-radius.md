# Этап 05 — домен, АРМ, RADIUS + Squid, аналоги Secret Net

Этап выполняется в два захода. Часть А (этот файл сейчас): контроллер домена dc на Samba AD,
ввод arm1 в домен, вход доменным пользователем, PAM (faillock, pwquality). Часть Б (RADIUS,
Squid на fw-int, inet, аналоги Secret Net, таблица логов, вход через VPN доменным пользователем)
будет дописана в следующей сессии.

## Цель
Поднять контроллер домена `gis.local` на открытом ПО вместо Windows Server, ввести АРМ
(Debian вместо Windows 10) в домен, настроить вход сотрудников доменными учётками, парольную
политику домена и блокировку учётки на АРМ после нескольких неудачных попыток входа.

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

## Отступления от схемы и причины
1. Вместо Windows Server DC используется Samba AD DC, вместо Windows 10 АРМ Debian-клиент с SSSD (решение группы, см. `prompts/00-context.md`).
2. NT ACL на sysvol хранятся в xattr `user.NTACL`, а не в `security.NTACL` (опция `acl_xattr:security_acl_name`). Для `security.*` контейнеру нужен `CAP_SYS_ADMIN`, его не давали, `--privileged` тоже не нужен. На работу домена это не влияет, отличие только в месте хранения ACL. Запасной вариант (MIT Kerberos + OpenLDAP) не понадобился.
3. Атрибуты RFC2307 (uidNumber/gidNumber) пользователям не заполняли, SSSD вычисляет UID/GID из SID (`ldap_id_mapping = true`). Из-за этого номера UID зависят от SID домена и меняются после повторной провизии с нуля (при первом запуске были 481001108, на свежем стенде 1357001108).
4. Групповые политики не настраивали, `ad_gpo_access_control = permissive` (GPO не мешают входу). Доступ к АРМ ограничен фильтром SSSD по группам Admin и Workgroup.
5. В `/etc/pam.d/sshd` на arm1 `pam_loginuid` переведён из `required` в `optional`: без `CAP_AUDIT_CONTROL` контейнер не может записать loginuid, и сессия sshd рвалась бы.
6. Двухфакторную аутентификацию (электронный ключ + пароль из документации ГИС) не моделировали, только пароль.
7. Блокировка работает на двух уровнях: на arm1 faillock блокирует после 3 попыток, в домене после 5. Порог на АРМ ниже, поэтому подбор пароля через arm1 упирается в faillock раньше, чем учётка блокируется во всём домене (после неудачных попыток и успешного входа в домене `badPwdCount: 0`).

## Проблемы и как решили
1. **Администратор домена входил на АРМ, хотя не состоит в Admin/Workgroup.** В первой версии `common-account` pam_unix и pam_sss стояли как альтернативы. pam_unix в фазе account возвращает success для любого пользователя, которого видит NSS (в том числе доменного через SSSD), поэтому до pam_sss и `ad_access_filter` дело не доходило. Сделали как в штатном профиле Debian для SSSD: pam_sss отдельной обязательной строкой после pam_unix (`[default=bad success=ok user_unknown=ignore]`). После этого `Access denied for user Administrator by PAM account configuration`.
2. **`chpasswd` в entrypoint arm1 перестал задавать пароль armuser.** После включения pwquality chpasswd идёт через PAM, а словаря cracklib в образе не было: `BAD PASSWORD: The password fails the dictionary check - error loading dictionary`. Добавили пакет `cracklib-runtime`, словарная проверка заработала.
3. **Повторный ввод в домен после пересоздания контейнера.** Keytab живёт в контейнере и теряется при пересоздании, а учётка ARM1$ на dc остаётся. Проверили: `adcli join` находит существующую учётку (`Found computer account for ARM1$`) и просто обновляет пароль и keytab, ошибки нет.
4. **Ложное срабатывание `set -e` в entrypoint dc (найдено при написании).** Проверка членства в группе через `samba-tool ... | grep -q` под `pipefail` могла упасть из-за SIGPIPE. Вывод сначала сохраняется в переменную, потом grep.
5. Пароль администратора передаётся `samba-tool domain provision` и `samba-tool user create` аргументом (так устроены эти команды), он виден в списке процессов на время провизии. Для учебного стенда допустимо, на arm1 пароль передаётся adcli через stdin.
