#!/bin/sh
set -eu
. /usr/local/lib/gis-lib.sh

IF=$(iface_for_subnet 192.168.100)
ip route replace default via 192.168.100.1 dev "$IF"

FTP_BACKUP_PASSWORD="${FTP_BACKUP_PASSWORD:?нужен пароль ftp в stand/secrets/stand.env}"

# pam_shells.so (используется vsftpd) пускает только пользователей с shell из /etc/shells.
# /usr/sbin/nologin туда не входит по умолчанию — добавляем явно, чтобы запретить
# интерактивный логин (sshd/su на этом узле всё равно нет), но разрешить FTP.
grep -qx /usr/sbin/nologin /etc/shells || echo /usr/sbin/nologin >> /etc/shells

mkdir -p /srv/ftp/ftpbackup
# "backup" занят системной учёткой Debian (uid 34, home /var/backups) — используем другое имя.
id ftpbackup >/dev/null 2>&1 || useradd -d /srv/ftp/ftpbackup -s /usr/sbin/nologin ftpbackup
chown ftpbackup:ftpbackup /srv/ftp/ftpbackup
chmod 750 /srv/ftp/ftpbackup
echo "ftpbackup:$FTP_BACKUP_PASSWORD" | chpasswd

mkdir -p /var/log/vsftpd /var/run/vsftpd/empty
: > /var/log/vsftpd/vsftpd.log

# Мастер-процесс vsftpd 3.0.5 в контейнере изредка падает с SIGSEGV (код 139) после обычной сессии,
# причина не установлена (см. PROGRESS.md, «Известные проблемы»). Перезапускаем его за 1 с и пишем
# код выхода в restarts.log, чтобы падения были видны, а не пропадали вместе с контейнером.
pid=
trap '[ -z "$pid" ] || kill "$pid" 2>/dev/null; exit 0' TERM INT
while true; do
    /usr/sbin/vsftpd /etc/vsftpd.conf &
    pid=$!
    rc=0
    wait "$pid" || rc=$?
    echo "$(date '+%F %T') vsftpd завершился с кодом $rc, перезапуск" >> /var/log/vsftpd/restarts.log
    sleep 1
done
