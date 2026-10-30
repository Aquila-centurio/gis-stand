FROM gis-base

RUN apt-get update && apt-get install -y --no-install-recommends chromium wireguard-tools openssh-client \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY wg-prepare.sh /usr/local/bin/wg-prepare.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/wg-prepare.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
