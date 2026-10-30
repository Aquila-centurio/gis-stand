#!/bin/bash
# Контроллер домена gis.local на Samba AD DC.
# Провизия выполняется один раз (база лежит в named volume), пользователи, группы и
# парольная политика применяются при каждом старте идемпотентно.
set -euo pipefail
. /usr/local/lib/gis-lib.sh

IF=$(iface_for_subnet 192.168.200)
ip route replace default via 192.168.200.1 dev "$IF"

DC_ADMIN_PASSWORD="${DC_ADMIN_PASSWORD:?нужен DC_ADMIN_PASSWORD в stand/secrets/stand.env}"
DOMAIN_USER_PASSWORD="${DOMAIN_USER_PASSWORD:?нужен DOMAIN_USER_PASSWORD в stand/secrets/stand.env}"

REALM=GIS.LOCAL
DOMAIN=GIS
DC_IP=192.168.200.20

# База (/var/lib/samba) и smb.conf (/etc/samba) лежат в named volume: провизия один раз.
if [ ! -f /var/lib/samba/private/sam.ldb ]; then
    echo "[dc] провизия домена $REALM"
    rm -f /etc/samba/smb.conf
    # acl_xattr:security_acl_name=user.NTACL: NT ACL на sysvol пишутся в xattr user.*,
    # а не security.* (для security.* нужен CAP_SYS_ADMIN, его контейнеру не даём).
    samba-tool domain provision \
        --server-role=dc \
        --use-rfc2307 \
        --dns-backend=SAMBA_INTERNAL \
        --realm="$REALM" \
        --domain="$DOMAIN" \
        --host-name=dc \
        --host-ip="$DC_IP" \
        --adminpass="$DC_ADMIN_PASSWORD" \
        --option="acl_xattr:security_acl_name = user.NTACL" \
        --option="interfaces = lo $IF" \
        --option="bind interfaces only = yes"
fi

cp /var/lib/samba/private/krb5.conf /etc/krb5.conf
printf 'search gis.local\nnameserver 127.0.0.1\n' > /etc/resolv.conf

# Группы и пользователи по документации ГИС (Guest в домен не заводим).
ensure_group() {
    samba-tool group show "$1" >/dev/null 2>&1 || samba-tool group add "$1" --description="$2"
}
ensure_user() { # login, имя, группа
    if ! samba-tool user show "$1" >/dev/null 2>&1; then
        samba-tool user create "$1" "$DOMAIN_USER_PASSWORD" --given-name="$2" \
            --mail-address="$1@gis.local"
    fi
    # Вывод сначала в переменную: grep -q в конвейере под pipefail дал бы ложный SIGPIPE.
    local members
    members=$(samba-tool group listmembers "$3")
    grep -qx "$1" <<<"$members" || samba-tool group addmembers "$3" "$1"
}

ensure_group Admin "Администраторы ИБ и ЗИ"
ensure_group Workgroup "Сотрудники архива"
ensure_user sysadmin "Администратор отдела ИБ" Admin
ensure_user secadmin "Специалист отдела ЗИ" Admin
ensure_user archhead "Начальник архива" Workgroup
ensure_user archstaff1 "Сотрудник архива" Workgroup

# Парольная политика домена.
samba-tool domain passwordsettings set \
    --complexity=on \
    --store-plaintext=off \
    --history-length=5 \
    --min-pwd-length=10 \
    --min-pwd-age=0 \
    --max-pwd-age=90 \
    --account-lockout-threshold=5 \
    --account-lockout-duration=15 \
    --reset-account-lockout-after=15 >/dev/null

# Журнал аутентификации (этап 05, часть Б): auth_audit:3 пишет в log.samba каждую проверку
# пароля и выдачу билета Kerberos (кто, откуда, успех/ошибка). Правим при каждом старте,
# т.к. smb.conf в volume и после первой провизии больше не создаётся.
sed -i '/^\s*log level\s*=/d' /etc/samba/smb.conf
sed -i 's/^\[global\]$/[global]\n\tlog level = 1 auth_audit:3/' /etc/samba/smb.conf

echo "[dc] запуск samba"
exec samba --foreground --no-process-group
