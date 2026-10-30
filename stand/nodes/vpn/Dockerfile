FROM gis-base

RUN apt-get update && apt-get install -y --no-install-recommends wireguard-tools \
    && rm -rf /var/lib/apt/lists/*

COPY nft/vpn.nft /etc/nft/vpn.nft
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
