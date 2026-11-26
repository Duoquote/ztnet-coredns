FROM ubuntu:24.04

ARG COREDNS_VERSION=1.15.0
ARG ZEROTIER_VERSION=1.16.2
ARG TARGETARCH

RUN set -eux; \
    arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg \
        jq \
        supervisor; \
    curl -fsSL https://download.zerotier.com/contact%40zerotier.com.gpg \
        | gpg --dearmor -o /usr/share/keyrings/zerotier.gpg; \
    echo "deb [signed-by=/usr/share/keyrings/zerotier.gpg] https://download.zerotier.com/debian/noble noble main" \
        > /etc/apt/sources.list.d/zerotier.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends "zerotier-one=${ZEROTIER_VERSION}"; \
    base="https://github.com/coredns/coredns/releases/download/v${COREDNS_VERSION}"; \
    file="coredns_${COREDNS_VERSION}_linux_${arch}.tgz"; \
    curl -fsSL -o "/tmp/${file}" "${base}/${file}"; \
    curl -fsSL -o "/tmp/${file}.sha256" "${base}/${file}.sha256"; \
    (cd /tmp && sha256sum -c "${file}.sha256"); \
    tar -xzf "/tmp/${file}" -C /usr/local/bin coredns; \
    mkdir -p /etc/coredns; \
    apt-get purge -y --auto-remove gnupg; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY configs/coredns.conf /etc/supervisor/conf.d/coredns.conf
COPY configs/zerotier.conf /etc/supervisor/conf.d/zerotier.conf
COPY configs/zt2zone.conf /etc/supervisor/conf.d/zt2zone.conf

COPY --chmod=755 scripts/zt2zone.sh scripts/zone-updater.sh /usr/local/bin/
COPY configs/Corefile /etc/coredns/Corefile

VOLUME /var/lib/zerotier-one

CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]
