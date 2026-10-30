FROM gis-base

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends freeradius freeradius-utils \
    && rm -rf /var/lib/apt/lists/*

# Журнал аутентификации: каждая попытка (Login OK / Login incorrect) пишется в radius.log.
# Пароли в лог не пишем (auth_badpass/auth_goodpass остаются no).
RUN sed -i 's/^\(\s*auth\s*=\s*\)no/\1yes/' /etc/freeradius/3.0/radiusd.conf

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
