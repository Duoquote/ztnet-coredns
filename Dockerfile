FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
        curl \
        gnupg \
        supervisor \
        jq \
    && \
    curl -s https://install.zerotier.com/ | bash && \
    curl -sL https://github.com/coredns/coredns/releases/download/v1.11.3/coredns_1.11.3_linux_amd64.tgz -o /tmp/coredns.tgz && \
    tar -xvf /tmp/coredns.tgz -C /usr/local/bin/ && \
    mkdir -p /etc/coredns && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY configs/coredns.conf /etc/supervisor/conf.d/coredns.conf
COPY configs/zerotier.conf /etc/supervisor/conf.d/zerotier.conf
COPY configs/zt2zone.conf /etc/supervisor/conf.d/zt2zone.conf

COPY scripts/zt2zone.sh /etc/zerotier/zt2zone.sh
COPY configs/Corefile /etc/coredns/Corefile

VOLUME /var/lib/zerotier-one

CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]