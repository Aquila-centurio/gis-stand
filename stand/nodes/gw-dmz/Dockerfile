FROM gis-base

COPY nft/gw-dmz-protect.nft /etc/nft/gw-dmz-protect.nft
COPY nft/gw-dmz-audit.nft /etc/nft/gw-dmz-audit.nft
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
