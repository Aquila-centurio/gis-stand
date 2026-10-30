<?php
function gis_db() {
    static $conn = null;
    if ($conn === null) {
        $password = getenv('WEBAPP_DB_PASSWORD');
        $conn = @pg_connect("host=192.168.200.10 port=5432 dbname=site user=webapp password=$password connect_timeout=3");
        if (!$conn) {
            http_response_code(500);
            die('Не удалось подключиться к базе данных.');
        }
    }
    return $conn;
}
