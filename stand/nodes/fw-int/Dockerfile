FROM gis-base

ENV DEBIAN_FRONTEND=noninteractive
# squid (с хелпером basic_radius_auth) и radtest для проверки RADIUS со стороны клиента (NAS).
RUN apt-get update && apt-get install -y --no-install-recommends squid freeradius-utils \
    && rm -rf /var/lib/apt/lists/*

COPY nft/fw-int-protect.nft /etc/nft/fw-int-protect.nft
COPY nft/fw-int-audit.nft /etc/nft/fw-int-audit.nft
COPY squid.conf /etc/squid/squid.conf
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
