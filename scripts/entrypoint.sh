#!/bin/bash
# Validate the configuration, write the CoreDNS config and an initial zone
# file, then start supervisord.

set -euo pipefail

err() { >&2 echo "entrypoint: ERROR: $*"; }

missing=0
for var in NETWORK_ID ZTNET_API_HOST ZTNET_API_TOKEN; do
  if [[ -z "${!var:-}" ]]; then
    err "$var is not set"
    missing=1
  fi
done
(( missing == 0 )) || exit 1

read -r -a networks <<<"${NETWORK_ID//,/ }"
for network in "${networks[@]}"; do
  if ! [[ "$network" =~ ^[0-9a-fA-F]{16}$ ]]; then
    err "invalid network ID '$network' (expected 16 hex characters)"
    exit 1
  fi
done

DNS_DOMAIN="${DNS_DOMAIN:-zt.vpn}"
export DNS_DOMAIN="${DNS_DOMAIN%.}"
export DNS_UPSTREAM="${DNS_UPSTREAM:-1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4}"
export ZONE_FILE="${ZONE_FILE:-/etc/coredns/zt.zone}"

# Write a Corefile from the environment unless a custom one is provided.
if [[ -z "${COREFILE:-}" ]]; then
  export COREFILE=/etc/coredns/Corefile
  cat >"$COREFILE" <<CONF
${DNS_DOMAIN}:53 {
  file ${ZONE_FILE} {
    reload 10s
  }
  errors
}

.:53 {
  forward . ${DNS_UPSTREAM}
  cache 30
  errors
}
CONF
elif [[ ! -f "$COREFILE" ]]; then
  err "COREFILE points to $COREFILE, which does not exist"
  exit 1
fi

# CoreDNS needs a zone file to load. Start with an empty zone; the zone
# updater replaces it after the first successful API call.
if [[ ! -f "$ZONE_FILE" ]]; then
  cat >"$ZONE_FILE" <<ZONE
\$ORIGIN ${DNS_DOMAIN}.
\$TTL 600
@ IN SOA ns1.${DNS_DOMAIN}. admin.${DNS_DOMAIN}. ( 1 10800 3600 604800 600 )
@ IN NS ns1.${DNS_DOMAIN}.
ZONE
  chmod 644 "$ZONE_FILE"
fi

# Join the configured networks on start. zerotier-one joins every network
# that has a file in networks.d.
if [[ "${ZT_AUTO_JOIN:-true}" == "true" ]]; then
  mkdir -p /var/lib/zerotier-one/networks.d
  for network in "${networks[@]}"; do
    touch "/var/lib/zerotier-one/networks.d/${network,,}.conf"
  done
fi

exec /usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf
