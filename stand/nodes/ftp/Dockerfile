FROM gis-base

# postgresql-client не нужен для работы vsftpd, но используется для проверки pg_hba
# с "чужого" хоста (см. results/02-dmz-services.md).
RUN apt-get update && apt-get install -y --no-install-recommends vsftpd postgresql-client \
    && rm -rf /var/lib/apt/lists/*

COPY vsftpd.conf /etc/vsftpd.conf
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
