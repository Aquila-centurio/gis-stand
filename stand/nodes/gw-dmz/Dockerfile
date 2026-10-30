FROM gis-base

RUN apt-get update && apt-get install -y --no-install-recommends suricata \
    && rm -rf /var/lib/apt/lists/*

COPY nft/gw-dmz-protect.nft /etc/nft/gw-dmz-protect.nft
COPY nft/gw-dmz-audit.nft /etc/nft/gw-dmz-audit.nft
COPY suricata/suricata.yaml.tmpl /etc/suricata/suricata.yaml.tmpl
COPY suricata/local.rules /etc/suricata/rules/local.rules
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
