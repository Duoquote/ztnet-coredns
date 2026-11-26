#!/bin/bash
# zt2zone: fetch authorized members of one or more ZTNet networks and print
# a CoreDNS zone file to stdout.
#
# Usage: zt2zone.sh <network-id> [<network-id> ...]
#
# Based on: https://ztnet.network/usage/create_dns_host

set -euo pipefail

ZTNET_API_HOST="${ZTNET_API_HOST:-}"
ZTNET_API_TOKEN="${ZTNET_API_TOKEN:-}"
ORG_ID="${ORG_ID:-}"
DNS_DOMAIN="${DNS_DOMAIN:-zt.vpn}"
DNS_TTL="${DNS_TTL:-600}"
ZTNET_API_RETRIES="${ZTNET_API_RETRIES:-3}"
ZTNET_API_RETRY_DELAY="${ZTNET_API_RETRY_DELAY:-5}"
ZTNET_API_TIMEOUT="${ZTNET_API_TIMEOUT:-30}"

err() { >&2 echo "zt2zone: ERROR: $*"; }

[[ -z "$ZTNET_API_TOKEN" ]] && { err "ZTNET_API_TOKEN is not set"; exit 1; }
[[ -z "$ZTNET_API_HOST" ]] && { err "ZTNET_API_HOST is not set"; exit 1; }
[[ $# -eq 0 ]] && { err "at least one network ID is required"; exit 1; }

DNS_DOMAIN="${DNS_DOMAIN%.}"
API_URL="${ZTNET_API_HOST%/}/api/v1"

TMP_BODY="$(mktemp)"
trap 'rm -f "$TMP_BODY"' EXIT

# Print the members of a network as JSON. Retries on connection errors,
# rate limiting (429) and server errors (5xx). Fails immediately on other
# HTTP errors, such as an invalid token or an unknown network.
get_network_members() {
  local network="$1" url status attempt=1

  if [[ -z "$ORG_ID" ]]; then
    url="${API_URL}/network/${network}/member"
  else
    url="${API_URL}/org/${ORG_ID}/network/${network}/member"
  fi

  while :; do
    status="$(curl -sS -L \
      --connect-timeout 10 \
      --max-time "$ZTNET_API_TIMEOUT" \
      -H "x-ztnet-auth: ${ZTNET_API_TOKEN}" \
      -H "Accept: application/json" \
      -o "$TMP_BODY" \
      -w '%{http_code}' \
      "$url")" || status="000"

    if [[ "$status" == "200" ]]; then
      if jq -e 'type == "array"' "$TMP_BODY" >/dev/null 2>&1; then
        cat "$TMP_BODY"
        return 0
      fi
      err "network $network: response is not a JSON array: $(head -c 300 "$TMP_BODY")"
    elif [[ "$status" != "000" && "$status" != "429" && "$status" != 5* ]]; then
      err "network $network: HTTP $status: $(head -c 300 "$TMP_BODY" 2>/dev/null)"
      return 1
    else
      err "network $network: request failed (HTTP $status), attempt $attempt of $ZTNET_API_RETRIES"
    fi

    if (( attempt >= ZTNET_API_RETRIES )); then
      return 1
    fi
    attempt=$((attempt + 1))
    sleep "$ZTNET_API_RETRY_DELAY"
  done
}

# Turn a member list into zone records. Member names are lowercased and
# reduced to valid DNS labels; members without a usable name fall back to
# their ZeroTier member ID. IPv4 addresses get A records, IPv6 get AAAA.
members_to_records() {
  jq -r --arg domain "$DNS_DOMAIN" '
    .[]
    | select(.authorized == true and (.deleted // false) == false)
    | ((.name // "")
        | ascii_downcase
        | gsub("[^a-z0-9-]+"; "-")
        | gsub("^-+|-+$"; "")
        | .[0:63]
        | gsub("-+$"; "")) as $clean
    | (if $clean == "" then .id else $clean end) as $label
    | (.ipAssignments // [])[]
    | (if test(":") then "AAAA" else "A" end) as $type
    | "\($label).\($domain).\tIN\t\($type)\t\(.)",
      "*.\($label).\($domain).\tIN\t\($type)\t\(.)"
  '
}

records=""
for network in "$@"; do
  members="$(get_network_members "$network")"
  records+="; Records for network ID: ${network}"$'\n'
  records+="$(members_to_records <<<"$members")"$'\n'
done

echo "; ZeroTier DNS records for *.${DNS_DOMAIN}"
echo "\$ORIGIN ${DNS_DOMAIN}."
echo "\$TTL ${DNS_TTL}"
echo "@ IN SOA ns1.${DNS_DOMAIN}. admin.${DNS_DOMAIN}. ( $(date +%s) 10800 3600 604800 ${DNS_TTL} )"
echo "@ IN NS ns1.${DNS_DOMAIN}."
printf '%s' "$records"
