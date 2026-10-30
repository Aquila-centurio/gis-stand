# Этап 02 — сервисы ДМЗ и БД

## Цель
Заменить заглушки web/ftp/db из этапа 01 на реальные сервисы ресурса «Интернет-сайт Счётной палаты РФ»:
Apache+PHP с HTTPS и учебной XSS-уязвимостью в поиске, vsftpd с бэкапом по FTP, PostgreSQL с ограниченной
учётной записью `webapp`. Показать сегментацию, ограничение доступа к БД и факт появления HTTPS.

## Что сделано
- **db** (intra .10): пакет `postgresql` (кластер 17, создаётся postinst'ом при сборке образа).
  `listen_addresses` ограничен адресом узла и `localhost` (без прослушивания всех интерфейсов). База
  `site`, таблицы `news`, `documents` (учебные данные) и `internal_notes` (без доступа webapp — для
  проверки ограничения прав). `pg_hba.conf` пускает `webapp` только с 192.168.100.10/32 (web), всё
  остальное — `reject`. Роль `webapp`: `SELECT` только на `news`/`documents`. Инициализация
  (`init.sql`) идемпотентна — безопасно выполняется при каждом старте контейнера.
- **web** (dmz .10): Apache 2.4 + mod_php + php-pgsql. Самоподписанный TLS-сертификат (создаётся при
  сборке образа, `openssl req -x509`, CN=198.51.100.1, 10 лет). Решение по HTTP/HTTPS: порт 80 отдаёт только
  `Redirect permanent` на 443, сам сайт работает лишь по HTTPS. Страницы: `index.php` (главная),
  `news.php` (новости из БД), `documents.php` (список документов из БД), `search.php` (поиск по
  новостям). `search.php` намеренно выводит параметр `q` в HTML без `htmlspecialchars` — помечено
  комментарием `// Учебная уязвимость` в коде, нужно для демонстрации IDS/IPS на этапе 03.
- **ftp** (dmz .11): vsftpd 3.0.5. Анонимный доступ выключен, локальный пользователь `ftpbackup`
  (имя `backup` оказалось занято системной учёткой Debian, см. «Проблемы и как решили»), chroot в
  `/srv/ftp/ftpbackup`, `allow_writeable_chroot=yes` (жильё пользователя и так его собственный chroot,
  других пользователей на узле нет). Диапазон пассивных портов 21100-21110, как зафиксировано в
  правилах МЭ на этапе 01.
- **backup.sh** (на узле db, запуск вручную): `pg_dump site` → загрузка по FTP (`curl --ftp-pasv -T`)
  на узел ftp под `ftpbackup`.
- Правила `fw-int` обновлены: добавлено `db → ftp` (порты 21 и 21100-21110, нужно для backup.sh) и
  расширено существующее правило `arm1 → ftp` диапазоном пассивных портов (раньше там был только
  порт 21 — не хватало бы для пассивной передачи данных, когда arm1 появится в этапе 05). Правила
  `gw-dmz` не менялись — там диапазон intra→ftp уже был заложен в этапе 01 по подсети `192.168.200.0/24`.
- Секреты: `stand/secrets/stand.env` (gitignore) с `WEBAPP_DB_PASSWORD` и `FTP_BACKUP_PASSWORD`,
  создаётся автоматически `up.sh`, если отсутствует. Значения — `results/00-summary.md`.
- `stand/scripts/shot-web.sh`: снимает скриншот страницы из контейнера `client` headless-хромиумом
  (`chromium --headless=new --no-sandbox`, добавлен в образ `client`).

## Конфигурация

### pg_hba.conf (db)
```
local   all             postgres                                peer
local   all             all                                     peer
host    all             all             127.0.0.1/32            md5
host    site            webapp          192.168.100.10/32       md5
host    all             all             0.0.0.0/0               reject
```
Полный файл генерируется в `stand/nodes/db/entrypoint.sh`.

### Права webapp (init.sql)
```sql
GRANT CONNECT ON DATABASE site TO webapp;
GRANT USAGE ON SCHEMA public TO webapp;
GRANT SELECT ON news, documents TO webapp;
REVOKE ALL ON internal_notes FROM webapp;
```
Полный файл: `stand/nodes/db/init.sql`.

### Apache — виртуальные хосты (web)
Полный файл: `stand/nodes/web/apache/gis-site.conf`
```
<VirtualHost *:80>
    ServerName 198.51.100.1
    Redirect permanent / https://198.51.100.1/
</VirtualHost>

<VirtualHost *:443>
    ServerName 198.51.100.1
    DocumentRoot /var/www/site
    SSLEngine on
    SSLCertificateFile /etc/ssl/gis/web.crt
    SSLCertificateKeyFile /etc/ssl/gis/web.key
    ...
</VirtualHost>
```

### search.php — учебная уязвимость (web)
```php
// Учебная уязвимость: поисковая строка выводится в HTML без htmlspecialchars,
// намеренно для демонстрации XSS и срабатывания IDS/IPS на этапе 03.
echo $_GET['q'];
```
Сам SQL-запрос к БД при этом параметризован (`pg_query_params`), SQL-инъекции нет — уязвимость только
отражённый XSS, как и требовалось.

### vsftpd.conf (ftp), ключевое
```
anonymous_enable=NO
local_enable=YES
chroot_local_user=YES
allow_writeable_chroot=YES
pasv_enable=YES
pasv_min_port=21100
pasv_max_port=21110
pasv_address=192.168.100.11
seccomp_sandbox=NO
```
Полный файл: `stand/nodes/ftp/vsftpd.conf`. «Зачем» `seccomp_sandbox=NO` — см. «Отступления».

### nftables fw-int (protect), изменения этапа 02
Полный файл: `stand/nodes/fw-int/nft/fw-int-protect.nft`
```
ip saddr 192.168.200.31 ip daddr 192.168.100.11 tcp dport { 21, 21100-21110 } counter name c_int_arm_to_ftp accept
ip saddr 192.168.200.10 ip daddr 192.168.100.11 tcp dport { 21, 21100-21110 } counter name c_int_db_to_ftp accept
```
Правило `gw-dmz` из этапа 01 (`ip saddr 192.168.200.0/24 ip daddr 192.168.100.11 tcp dport { 21, 21100-21110 }`)
без изменений покрывает и db, и будущий arm1 — диапазон портов там был заложен заранее.

## Проверка функционирования

### Проверка 1 — protect: client → https://198.51.100.1/ отдаёт сайт
- Команда: `docker exec gis-client curl -k -sS -I -m5 https://198.51.100.1/`
- Ожидание: `200 OK`, `Server: Apache`.
- Получили: `HTTP/1.1 200 OK`, `Server: Apache/2.4.69 (Debian)`.
- Скрин: screens/02-curl-https-headers.png
- Итог: PASS

### Проверка 2 — protect: http редиректит на https
- Команда: `docker exec gis-client curl -sS -I -m5 http://198.51.100.1/`
- Ожидание: `301`, `Location: https://198.51.100.1/`.
- Получили: ровно так.
- Скрин: screens/02-curl-http-redirect.png
- Итог: PASS

### Проверка 3 — protect: страница новостей показывает данные из БД
- Команда: `shot-web.sh 02-site-https https://198.51.100.1/news.php` (скрин браузера) + текстом
  `docker exec gis-client curl -k -sS -m5 https://198.51.100.1/news.php`
- Ожидание: 3 учебные новости из таблицы `news`.
- Получили: 3 `<article>` с заголовками и датами, совпадает с содержимым `init.sql`.
- Скрин: screens/02-site-https.png (браузер), screens/02-news-db-data.png (curl)
- Итог: PASS

### Проверка 4 — учебная XSS в поиске отражается без экранирования
- Команда: `docker exec gis-client curl -k -sS -m5 'https://198.51.100.1/search.php?q=%3Cscript%3Ealert(1)%3C/script%3E'`
- Ожидание: `<script>alert(1)</script>` в ответе буквально, не как `&lt;script&gt;`.
- Получили: именно так — сырой тег присутствует в HTML.
- Скрин: screens/02-xss-search-reflect.png
- Итог: PASS (задел для IDS на этапе 03)

### Проверка 5 — protect: attacker → 198.51.100.1:21,5432 недоступны, ICMP внутрь не проходит
- Команда: `docker exec gis-attacker nmap -sT -Pn -T4 -p 21,22,80,443,5432 198.51.100.1`;
  `docker exec gis-attacker sh -c 'ping -c3 -W1 192.168.100.11; ping -c3 -W1 192.168.200.10'`
- Ожидание: 21/5432/22 closed, 80/443 open; ping — 100% потерь.
- Получили: `21 closed`, `22 closed`, `80 open`, `443 open`, `5432 closed`; оба ping — 100% packet loss.
- Скрин: screens/02-nmap-public-closed.png, screens/02-ping-attacker-dmz-intra.png
- Итог: PASS

### Проверка 6 — protect: прямой доступ к dmz в обход публичного адреса по-прежнему закрыт
- Команда: `docker exec gis-attacker nmap -sT -Pn -T4 -p 21,443,5432 192.168.100.10 192.168.100.11`
- Ожидание: всё `filtered` (правило `ct status dnat` из этапа 01 продолжает действовать).
- Получили: все порты `filtered` на обоих хостах.
- Скрин: screens/02-nmap-dmz-direct.png
- Итог: PASS

### Проверка 7 — web → db под webapp: запрос проходит
- Команда: `docker exec gis-web php -r '... pg_connect(...); SELECT count(*) FROM news ...'`
- Ожидание: успешное соединение, `news count: 3`.
- Получили: `news count: 3`.
- Скрин: screens/02-webapp-select-ok.png
- Итог: PASS

### Проверка 8 — webapp не видит internal_notes и не может менять схему
- Команда: тот же PHP-скрипт, `SELECT * FROM internal_notes` и `ALTER TABLE news ADD COLUMN x int`.
- Ожидание: обе операции отклонены правами.
- Получили: `internal_notes: ERROR: permission denied for table internal_notes`;
  `ALTER TABLE: ERROR: must be owner of table news`.
- Скрин: screens/02-webapp-permission-denied.png
- Итог: PASS

### Проверка 9 — webapp с другого хоста отклоняется pg_hba (не просто МЭ)
В обычном режиме `protect` пакет от ftp к db вообще не доходит (dmz→intra разрешено только для web на
`gw-dmz`) — значит проверка показала бы только срабатывание МЭ, а не pg_hba. Чтобы проверить именно
`pg_hba.conf` как самостоятельный рубеж защиты (не только сетевую сегментацию), на время теста включили
режим `audit` (ACL форварда отключён, пакет доходит до postgres), проверили, что `pg_hba` всё равно
отклоняет чужой хост, и вернули `protect`.
- Команда: `./scripts/mode.sh audit`; `docker exec -e PGPASSWORD=... gis-ftp psql -h 192.168.200.10 -U webapp -d site -c 'SELECT 1;'`; `./scripts/mode.sh protect`
- Ожидание: `pg_hba.conf rejects connection for host "192.168.100.11" ...` (хотя сеть пакет пропустила).
- Получили: ровно такая ошибка FATAL от postgres.
- Скрин: screens/02-pg-hba-reject.png
- Итог: PASS

### Проверка 10 — FTP: анонимный доступ отклонён
- Команда: `docker exec gis-db curl -sS -m5 ftp://192.168.100.11/`
- Ожидание: `530` (login denied), не листинг.
- Получили: `curl: (67) Access denied: 530`.
- Скрин: screens/02-ftp-anon-denied.png
- Итог: PASS

### Проверка 11 — backup.sh отрабатывает, файл появляется на ftp
- Команда: `docker exec gis-db backup.sh`, затем
  `docker exec gis-db curl -sS -m5 --ftp-pasv 'ftp://ftpbackup:...@192.168.100.11/'`
- Ожидание: сообщение об успешной загрузке, файл `site-<timestamp>.sql` виден в листинге.
- Получили: `Бэкап загружен на ftp: site-20261030-080612.sql`; в листинге оба файла (из двух запусков).
- Скрин: screens/02-backup-upload.png, screens/02-ftp-list-after-backup.png
- Итог: PASS

### Проверка 12 — FTP из ext недоступен, из intra доступен
- Из ext: порт 21 на публичном адресе `closed` (проверка 5, nmap); прямой адрес dmz — `filtered`
  (проверка 6). Из intra: db успешно логинится и грузит файл (проверки 10-11, источник — db, intra .10).
- Итог: PASS (данные — те же скрины, что и проверки 5, 6, 10, 11)

### Проверка 13 — nft list ruleset на gw-dmz после всех проверок
- Команда: `docker exec gis-gw-dmz nft list ruleset`
- Ожидание: счётчики легитимного трафика (`c_dmz_to_web`, `c_dmz_to_ftp`, `c_dmz_web_to_db`) ненулевые,
  `c_dmz_invalid`/`c_dmz_fwd_drop` — по ситуации (в этом прогоне запрещённого трафика через dmz не было,
  поэтому 0 — все злонамеренные попытки в сессии были направлены на fw-ext/публичный адрес и отражены
  там же, до gw-dmz).
- Получили: `c_dmz_to_web` 1, `c_dmz_to_ftp` 5, `c_dmz_web_to_db` 1, `c_dmz_invalid`/`c_dmz_fwd_drop` 0.
- Скрин: screens/02-nft-gwdmz-counters.png
- Итог: PASS

### Проверка 14 — версии пакетов (для отчёта)
- Команда: `apache2 -v`, `php -v`, `psql --version`, `dpkg -l vsftpd`
- Получили: Apache/2.4.69 (Debian), PHP 8.4.27, PostgreSQL 17.11 (Debian 17.11-0+deb13u1), vsftpd 3.0.5-0.2.
- Скрин: screens/02-versions.png
- Итог: PASS

### Проверка 15 — стенд поднимается с нуля
- Команда: `./scripts/down.sh && ./scripts/up.sh`, затем повтор проверок 1 и 3 (curl https, подсчёт
  `<article>` в news.php).
- Ожидание: тот же результат без ручных правок.
- Получили: `200 OK`, 3 новости — идентично первому прогону.
- Итог: PASS

## Свойства безопасности по мерам
- **Сегментация сети + МЭ (dmz/intra, правила fw-int/gw-dmz/fw-ext)** — доступность/целостность: сужает
  поверхность атаки, не даёт обратиться к db/ftp напрямую из ext или из произвольного хоста intra/dmz.
- **pg_hba.conf, ограничение webapp по адресу и базе** — конфиденциальность/целостность: второй,
  независимый от МЭ рубеж — проверка 9 показала, что он держит периметр, даже если МЭ временно
  отключён (режим `audit`, учения/ошибка конфигурации).
- **Минимальные права роли webapp (SELECT только на news/documents)** — конфиденциальность/целостность:
  даже при компрометации веб-приложения (например, через ту же учебную XSS, если её довести до RCE)
  нарушитель не сможет прочитать `internal_notes` или изменить схему БД.
- **HTTPS на web (самоподписанный сертификат)** — конфиденциальность/целостность трафика между client и
  web; HTTP (80) не отдаёт контент, только редиректит, снижает риск случайной передачи данных в
  открытом виде.
- **vsftpd: анонимный доступ выключен, chroot, фиксированный пассивный диапазон** — конфиденциальность/
  целостность: нельзя скачать/перезаписать файлы без учётки и нельзя выйти за пределы каталога бэкапов;
  фиксированный диапазон портов нужен и для предсказуемости правил МЭ.
- **Резервное копирование (backup.sh, pg_dump → ftp)** — доступность: восстановление данных сайта при
  потере базы.

## Отступления от схемы и причины
1. **FTP-пользователь назван `ftpbackup`, а не `backup`.** Имя `backup` уже занято системной учётной
   записью Debian (uid 34, home `/var/backups`, создаётся пакетом `base-passwd`). `useradd` молча
   пропускался (учётка с таким именем уже существовала), пароль выставлялся на системную учётку,
   vsftpd логинил пользователя в `/var/backups`, куда writable-доступа нет — отсюда `553 Could not
   create file` при STOR (разобрано ниже).
2. **`seccomp_sandbox=NO` в vsftpd.conf.** Без возможностей ядра, которые доступны контейнеру
   (`NET_ADMIN`, но не полный набор), встроенная seccomp-песочница vsftpd иногда мешает штатной работе
   в контейнерах; отключение не влияет на правила доступа МЭ или аутентификацию — это только внутренний
   механизм самозащиты демона.
3. **`allow_writeable_chroot=YES`.** Классическая рекомендация vsftpd — chroot-каталог не должен быть
   доступен на запись пользователю, которого в нём чрутят, иначе возможен побег из chroot через
   `/proc/self/cwd`-трюки с правами root внутри vsftpd. У нас единственный пользователь в контейнере —
   он же владелец каталога, предназначенного только для его файлов, других непривилегированных
   пользователей на узле нет — риск приняли как приемлемый для учебного стенда и записали явно.
4. **`postgresql-client` добавлен в образ `ftp`.** Нужен только для проверки 9 (подключение от имени
   `webapp` с «чужого» хоста). В рабочем процессе ftp он не используется.
5. **HTTP (80) не отдаёт контент, только редирект на HTTPS (443).** Явный выбор между «оба порта
   отдают сайт» и «80 только для редиректа» — выбрали редирект, он реалистичнее поведения боевого
   сайта.
6. **Правило `fw-int: arm1 → ftp` расширено диапазоном пассивных портов** (был только порт 21) —
   без этого на этапе 05 бэкап с arm1 работал бы только по управляющему соединению, без передачи
   данных.
7. **На `client` добавлен Chromium (headless) для `shot-web.sh`, запускается с `--no-sandbox`.**
   Полноценная песочница Chromium требует дополнительных возможностей ядра (userns/seccomp), которые
   решили не добавлять ради единственного скрипта для скриншотов; `client` и так изолирован
   docker-сетями стенда, риск приемлем.
8. **У сервиса `ftp` в `docker-compose.yml` стоит `init: true` (добавлено на этапе 06).** PID 1 в
   контейнере теперь `docker-init` (встроенный в Docker tini), vsftpd запускается его дочерним
   процессом. Причина в «Проблемах», п. 5. Хост не менялся: `docker-init` входит в состав Docker.

## Проблемы и как решили
1. **`FTP_BACKUP_PASSWORD` со знаком `#` ломал URL в `backup.sh`.** Исходное значение пароля
   `Backup#2026` передавалось в `curl ftp://user:pass@host/...` — curl трактует всё после `#` как
   fragment URL и обрезает оттуда username:password, из-за чего `curl` падал с «bad/illegal format».
   Сменили учебные пароли на значения без символов `#@/:%` (см. `results/00-summary.md`).
2. **`553 Could not create file` при загрузке на FTP.** См. «Отступления», п.1 — конфликт имени
   пользователя `backup` с системной учёткой Debian. Нашли через `curl -v` (показал
   `PWD → "/var/backups"` вместо ожидаемого домашнего каталога) и явную проверку
   `getent passwd backup`. Решение — переименовали пользователя в `ftpbackup`.
3. **`500 OOPS: vsftpd: not found: directory given in 'secure_chroot_dir'`.** vsftpd по умолчанию
   использует `/var/run/vsftpd/empty` для привилегий непривилегированных соединений — в свежем образе
   этого каталога нет. Добавили `mkdir -p /var/run/vsftpd/empty` в `entrypoint.sh`.
4. **`apt-get install` внутри уже запущенного контейнера (для диагностики) не работал.** Сети стенда
   изолированы от реального интернета по задумке (см. этап 01) — `docker exec` в контейнер, уже
   подключённый только к `gis_*`-сетям, не имеет внешнего доступа. Пакеты, нужные для диагностики/работы
   (в данном случае `postgresql-client` на ftp), добавили в `Dockerfile` — сборка образа идёт на хосте
   с обычной сетью, туда интернет есть.
5. **vsftpd падал с SIGSEGV (код 139), найдено на этапе 06.** При прогонах `check-all.sh` контейнер
   `gis-ftp` трижды завершился с кодом 139 (30.10 в 09:59:26, 10:09:58 и около 10:14:41 UTC),
   `OOMKilled=false`. vsftpd был PID 1 контейнера (`exec vsftpd` в `entrypoint.sh`). Что проверили:
   - `seccomp_sandbox=NO` стоит в `vsftpd.conf` с этого этапа (п. 2 «Отступлений»), то есть все три
     падения были уже с ним. Эта настройка на падение не влияет.
   - Сами FTP-сессии падение не вызывают. При vsftpd в роли PID 1 прошли 150 полных сессий Python
     `ftplib` с arm1 (login, LIST, STOR, RETR со сверкой содержимого, DELE, QUIT; 3 серии по 50, все
     успешны) и 40 итераций «анонимный вход с ответом 530 + `backup.sh` + листинг через curl» с db.
   - Причина воспроизводится одной командой: `docker exec gis-ftp sh -c 'sleep 1 & exit 0'`.
     Процесс `sleep` остаётся сиротой и переподвешивается на PID 1, то есть на vsftpd. Через секунду
     он завершается, SIGCHLD с чужим PID получает мастер-процесс vsftpd, и контейнер падает с кодом 139.
     Так получилось 3 раза из 3. По поведению видно, что vsftpd не рассчитан работать как init
     (забирать чужих сирот); исходный код обработчика SIGCHLD не разбирали. Какой именно процесс стал сиротой в исходных трёх
     падениях, не установили (в то время в контейнер ходили `docker exec` для диагностики).
   - Решение: `init: true` для `ftp` в `docker-compose.yml` (п. 8 «Отступлений»), `entrypoint.sh`
     снова заканчивается на `exec vsftpd`. Временный цикл-перезапуск с этапа 06 убран: он только
     скрывал падения. Проверка после правки: 3 сироты подряд, контейнер жив (`running`, зомби 0);
     50 полных сессий из 50; `check-all.sh` после чистого `down -v` + `up.sh`: 48 PASS из 48, в том
     числе новая проверка 02.9 «ftp переживает осиротевший процесс».
   - Замена vsftpd на pure-ftpd или proftpd не понадобилась: дефект был в способе запуска, а не в
     обработке FTP-сессий.

## Коммит
Коммит этапа 02 — после обновления `PROGRESS.md`.
