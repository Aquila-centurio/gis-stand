# Общие функции для entrypoint-скриптов узлов стенда gis.
# Подключается через ". /usr/local/lib/gis-lib.sh"

# iface_for_subnet <первые_октеты_подсети, напр. 192.168.50>
# Находит имя интерфейса по IP-адресу в заданной подсети (не доверяем нумерации eth0/eth1 от docker).
iface_for_subnet() {
    ip -4 -o addr show | awk -v pat="$1" '$4 ~ ("^" pat "\\.") {print $2; exit}'
}

GIS_MODE_FILE=/etc/gis/mode

gis_read_mode() {
    if [ -f "$GIS_MODE_FILE" ]; then
        cat "$GIS_MODE_FILE"
    else
        echo protect
    fi
}

gis_write_mode() {
    mkdir -p /etc/gis
    echo "$1" > "$GIS_MODE_FILE"
}
