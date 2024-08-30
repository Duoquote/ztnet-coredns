#!/bin/bash

# Reference: https://ztnet.network/usage/create_dns_host

set -eo pipefail

# Ensure ZTNET_API_TOKEN is set
[[ -z "$ZTNET_API_TOKEN" ]] && \
  >&2 echo "ERROR: must set ZTNET_API_TOKEN!" && \
  exit 1

# Ensure at least one network ID is provided
[ "$1" = "" ] && \
  >&2 echo "ERROR: must provide at least one network ID!" && \
  exit 1

# Domain for the DNS zone
ORG_ID="${ORG_ID:-}"
DNS_DOMAIN="${DNS_DOMAIN:-zt.vpn}"
ZTNET_API_HOST=${ZTNET_API_HOST:-"https://my.zerotier.com"}
API_URL="${ZTNET_API_HOST}/api/v1"
AUTH_HEADER="x-ztnet-auth: ${ZTNET_API_TOKEN}"

# Function to get network member information
get_network_members() {
  if [ -z "$ORG_ID" ]; then
    curl -sH "${AUTH_HEADER}" "${API_URL}/network/${1}/member/"
  else
    curl -sH "${AUTH_HEADER}" "${API_URL}/org/${ORG_ID}/network/${1}/member/"
  fi
}

# Start output for CoreDNS zone file
echo "; ZeroTier DNS records for *.$DNS_DOMAIN"
echo "\$TTL 600"
echo "@ IN SOA ns1.$DNS_DOMAIN. admin.$DNS_DOMAIN. ( $(date +%s) 10800 3600 604800 600 )"
echo "@ IN NS ns1.$DNS_DOMAIN."

# Process each network ID provided as argument
for NETWORK in $@; do
  echo "; Records for network ID: $NETWORK"
  # Fetch network members JSON and filter for authorized members
  members_json=$(get_network_members "$NETWORK")

  # Handle errors in fetching network members
  if [[ "$members_json" == *"error"* ]]; then
    >&2 echo "ERROR GET Network Members: $members_json"
    exit 1
  fi
  
  # Parse JSON and format as DNS records
  echo "$members_json" | jq -r --arg domain "$DNS_DOMAIN" '.[] | select(.authorized == true) | .ipAssignments[] as $ip | "\(.name).\($domain). IN A \($ip)"'
done