FROM gis-base

COPY nft/fw-ext-protect.nft /etc/nft/fw-ext-protect.nft
COPY nft/fw-ext-audit.nft /etc/nft/fw-ext-audit.nft
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
