#!/usr/bin/env sh

# DNS API for DuckDNS
#
# Report bugs at https://github.com/RockyTV/acme.sh/issues
#
# Set this environment variable to match your DuckDNS account token:
# DUCKDNS_TOKEN=aaaaaaaa-bbbb-cccc-dddddddddddd

########  Public functions #####################
# Usage: dns_duckdns_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_duckdns_add() {
  fulldomain=$1
  txtvalue=$2

  _info "Adding TXT record to DuckDNS domain"
  _debug "fulldomain: $fulldomain"
  _debug "txtvalue: $txtvalue"

  if ! _get_root "$fulldomain"; then
    _err "Domain does not exist."
    return 1
  fi
  
  if [ -z "$DUCKDNS_TOKEN" ]; then
    DUCKDNS_TOKEN=""
    _err "DuckDNS token is not defined."
    _err "Please export your account token to DUCKDNS_TOKEN and try again."
    return 1
  fi
  _saveaccountconf DUCKDNS_TOKEN "$DUCKDNS_TOKEN"
  
  duckdns_url="https://www.duckdns.org/update?domains=$_domain&token=$DUCKDNS_TOKEN&txt=$txtvalue"
  response=$(_get $duckdns_url)
  if [ $response != "OK" ]; then
    _err "Failed to update TXT record for DuckDNS domain."
    return 1
  fi
  
  return 0
}

# Usage: fulldomain txtvalue
# Remove the txt record after validation.
dns_duckdns_rm() {
  fulldomain=$1
  txtvalue=$2
  
  _info "Removing TXT record from DuckDNS domain"
  _debug "fulldomain: $fulldomain"
  _debug "txtvalue: $txtvalue"

  DUCKDNS_TOKEN="$(_read_conf "$ACCOUNT_CONF_PATH" "DUCKDNS_TOKEN")"
  _debug "DuckDNS token: $DUCKDNS_TOKEN"

  if ! _get_root "$fulldomain"; then
    _err "Domain does not exist."
    return 1
  fi

  duckdns_url="https://www.duckdns.org/update?domains=$_domain&token=$DUCKDNS_TOKEN&txt=&clear=true"
  response=$(_get $duckdns_url)
  if [ $response != "OK" ]; then
    _err "Failed to update TXT record for DuckDNS domain."
    return 1
  fi
  
  return 0
}

####################  Private functions below ##################################
# _acme-challenge.www.domain.com
# returns
# _domain=domain.com
_get_root() {
  domain=$1
  i="$(echo "$fulldomain" | tr '.' ' ' | wc -w)"
  i=$(_math "$i" - 1)

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    if [ -z "$h" ]; then
      return 1
    fi
    _domain="$h"
    return 0
  done
  _debug "$domain not found"
  return 1
}