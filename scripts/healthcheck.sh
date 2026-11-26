#!/bin/bash
# Docker health check: CoreDNS is serving, ZeroTier is online and the zone
# file was refreshed recently.

set -uo pipefail

ZONE_REFRESH_INTERVAL="${ZONE_REFRESH_INTERVAL:-30}"
ZONE_STATUS_FILE="${ZONE_STATUS_FILE:-/run/zt2zone/last-success}"
# Allow a few failed refreshes before reporting unhealthy.
max_age=$(( ZONE_REFRESH_INTERVAL * 3 ))
(( max_age < 300 )) && max_age=300

fail() { echo "unhealthy: $*"; exit 1; }

curl -fsS --max-time 3 http://127.0.0.1:8080/health >/dev/null \
  || fail "CoreDNS health endpoint is not responding"

zerotier-cli info 2>/dev/null | grep -q ONLINE \
  || fail "ZeroTier is not online"

[[ -f "$ZONE_STATUS_FILE" ]] \
  || fail "the zone has not been generated from the ZTNet API yet"

age=$(( $(date +%s) - $(stat -c %Y "$ZONE_STATUS_FILE") ))
(( age <= max_age )) \
  || fail "last successful zone update was ${age}s ago"

exit 0
