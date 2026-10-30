#!/bin/sh
set -eu
. /usr/local/lib/gis-lib.sh

IF=$(iface_for_subnet 192.168.200)
ip route replace default via 192.168.200.1 dev "$IF"

# Присоединение к домену и настройка АРМ — в этапе 05. Сейчас arm1 — заглушка с sshd,
# нужна как цель для проверки доступа VPN-клиента (этап 04: VPN-клиент -> arm1 tcp 22).
ARM_SSH_PASSWORD="${ARM_SSH_PASSWORD:?нужен пароль arm1 в stand/secrets/stand.env}"

mkdir -p /run/sshd
ssh-keygen -A >/dev/null

if ! id armuser >/dev/null 2>&1; then
    useradd -m -s /bin/sh armuser
fi
echo "armuser:${ARM_SSH_PASSWORD}" | chpasswd

exec /usr/sbin/sshd -D
