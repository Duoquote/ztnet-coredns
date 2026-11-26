#!/bin/bash
# Regenerate the CoreDNS zone file every ZONE_REFRESH_INTERVAL seconds.
#
# The new zone is written to a temporary file and moved into place, so
# CoreDNS never reads a partial file. If the ZTNet API cannot be reached,
# the previous zone file is kept.

set -uo pipefail

ZONE_FILE="${ZONE_FILE:-/etc/coredns/zt.zone}"
ZONE_REFRESH_INTERVAL="${ZONE_REFRESH_INTERVAL:-30}"
ZONE_STATUS_FILE="${ZONE_STATUS_FILE:-/run/zt2zone/last-success}"
ZT2ZONE="${ZT2ZONE:-/usr/local/bin/zt2zone.sh}"

# NETWORK_ID may hold several IDs separated by spaces or commas.
read -r -a networks <<<"${NETWORK_ID//,/ }"

if [[ ${#networks[@]} -eq 0 ]]; then
  >&2 echo "zone-updater: ERROR: NETWORK_ID is not set"
  exit 1
fi

if ! [[ "$ZONE_REFRESH_INTERVAL" =~ ^[0-9]+$ ]] || (( ZONE_REFRESH_INTERVAL < 1 )); then
  >&2 echo "zone-updater: ERROR: ZONE_REFRESH_INTERVAL must be a positive number of seconds"
  exit 1
fi

mkdir -p "$(dirname "$ZONE_STATUS_FILE")"

# Zone contents without the SOA line, whose serial changes on every run.
records_of() { grep -v ' IN SOA ' "$1"; }

update_zone() {
  local tmp count
  tmp="$(mktemp "${ZONE_FILE}.XXXXXX")" || return 1

  if ! "$ZT2ZONE" "${networks[@]}" >"$tmp"; then
    rm -f "$tmp"
    return 1
  fi

  if [[ -f "$ZONE_FILE" ]] && cmp -s <(records_of "$ZONE_FILE") <(records_of "$tmp"); then
    # Nothing changed. Keep the old file and serial so CoreDNS does not reload.
    rm -f "$tmp"
  else
    chmod 644 "$tmp"
    mv -f "$tmp" "$ZONE_FILE"
    count="$(grep -cE $'\tIN\t(A|AAAA)\t' "$ZONE_FILE" || true)"
    echo "zone-updater: wrote $ZONE_FILE ($count records)"
  fi

  touch "$ZONE_STATUS_FILE"
}

while :; do
  if ! update_zone; then
    >&2 echo "zone-updater: update failed, keeping the previous zone file"
  fi
  sleep "$ZONE_REFRESH_INTERVAL"
done
