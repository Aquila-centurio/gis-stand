# Сводка — учебные пароли стенда

Файл ведётся по правилу из `prompts/00-context.md`/`CLAUDE.md`: пароли стенда учебные (не боевые),
но сами значения не коммитятся — лежат в `stand/secrets/stand.env` (в `.gitignore`), создаются
автоматически `stand/scripts/up.sh` при первом запуске, если файла ещё нет.

## stand/secrets/stand.env (с этапа 02)

| Переменная | Значение | Где используется |
|---|---|---|
| `WEBAPP_DB_PASSWORD` | `Webapp2026stand` | роль PostgreSQL `webapp` (узел db), подключение из web (`site/db.php`) |
| `FTP_BACKUP_PASSWORD` | `Backup2026stand` | локальный пользователь vsftpd `ftpbackup` (узел ftp), `backup.sh` на db |

Без спецсимволов URL (`#@/:%`) — `FTP_BACKUP_PASSWORD` подставляется прямо в `ftp://` URL в
`backup.sh`, а `#` там обрывает строку как начало fragment (нашли на практике, см.
`results/02-dmz-services.md`, «Проблемы и как решили»).

Если `stand/secrets/stand.env` потерян/удалён — `up.sh` создаст его заново с этими же значениями.
