#!/bin/bash
# АРМ arm1: клиент домена gis.local (adcli + SSSD), sshd для доступа (в т.ч. через VPN, этап 04).
set -euo pipefail
. /usr/local/lib/gis-lib.sh

IF=$(iface_for_subnet 192.168.200)
ip route replace default via 192.168.200.1 dev "$IF"

ARM_SSH_PASSWORD="${ARM_SSH_PASSWORD:?нужен ARM_SSH_PASSWORD в stand/secrets/stand.env}"
DC_ADMIN_PASSWORD="${DC_ADMIN_PASSWORD:?нужен DC_ADMIN_PASSWORD в stand/secrets/stand.env}"

# DNS только на контроллер домена: через него находятся SRV-записи LDAP/Kerberos.
printf 'search gis.local\nnameserver 192.168.200.20\n' > /etc/resolv.conf

# Локальная учётка с этапа 04 (проверка VPN -> arm1:22 без домена) остаётся.
if ! id armuser >/dev/null 2>&1; then
    useradd -m -s /bin/bash armuser
fi
echo "armuser:${ARM_SSH_PASSWORD}" | chpasswd

# Ждём, пока dc начнёт отвечать по DNS и LDAP (после первой провизии это до минуты).
for i in $(seq 1 90); do
    if host -t SRV _ldap._tcp.gis.local >/dev/null 2>&1 && nc -z -w1 dc.gis.local 389; then
        break
    fi
    [ "$i" -eq 90 ] && { echo "[arm1] dc не ответил за 180 с" >&2; exit 1; }
    sleep 2
done

# Ввод в домен: учётная запись компьютера ARM1$ и /etc/krb5.keytab.
# При пересоздании контейнера keytab теряется, adcli join повторно использует существующую учётку.
if ! klist -k /etc/krb5.keytab 2>/dev/null | grep -qi 'ARM1\$@GIS.LOCAL'; then
    echo "[arm1] ввод в домен gis.local"
    printf '%s' "$DC_ADMIN_PASSWORD" | adcli join --domain=gis.local \
        --domain-controller=dc.gis.local --host-fqdn=arm1.gis.local \
        --login-user=Administrator --stdin-password --verbose
fi

mkdir -p /run/sshd /var/run/faillock
ssh-keygen -A >/dev/null
rm -f /var/run/sssd.pid
sssd -D

exec /usr/sbin/sshd -D -e
