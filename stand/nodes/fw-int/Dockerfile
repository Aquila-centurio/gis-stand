FROM gis-base

COPY nft/fw-int-protect.nft /etc/nft/fw-int-protect.nft
COPY nft/fw-int-audit.nft /etc/nft/fw-int-audit.nft
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
