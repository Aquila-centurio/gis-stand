FROM debian:trixie

RUN apt-get update && apt-get install -y --no-install-recommends \
        iproute2 \
        nftables \
        iputils-ping \
        iputils-tracepath \
        curl \
        tcpdump \
        netcat-openbsd \
        dnsutils \
        procps \
    && rm -rf /var/lib/apt/lists/*

COPY lib.sh /usr/local/lib/gis-lib.sh
