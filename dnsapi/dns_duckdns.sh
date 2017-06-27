#!/usr/bin/env sh

#Created by RaidenII, to use DuckDNS's API to add/remove text records
#06/27/2017

# Currently only support single domain access

# DuckDNS uses StartSSL as their cert provider
# Seems not supported natively on Linux
# So I fall back to HTTP for API
DuckDNS_API="http://www.duckdns.org/update"

########  Public functions #####################

#Usage: dns_duckdns_add _acme-challenge.domain.duckdns.org "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_duckdns_add() {
  fulldomain=$1
  txtvalue=$2

  # We'll extract the domain/username from full domain
  IFS='.' read -r -a fqdn <<< "$fulldomain"
  DuckDNS_domain="${fqdn[-3]}"

  if [ -z "$DuckDNS_domain" ]; then
    _err "Error extracting the domain."
    return 1
  fi

  if [ -z "$DuckDNS_token" ]; then
    DuckDNS_token=""
    _err "The token for your DuckDNS account is necessary."
    _err "You can look it up in your DuckDNS account."
    return 1
  fi

  # Now save the credentials.
  _saveaccountconf DuckDNS_domain "$DuckDNS_domain"
  _saveaccountconf DuckDNS_token "$DuckDNS_token"

  # Unfortunately, DuckDNS does not seems to support lookup domain through API
  # So I assume your credentials (which are your domain and token) are correct
  # If something goes wrong, we will get a KO response from DuckDNS

  # Now add the TXT record to DuckDNS
  _info "Trying to add TXT record"
  if _duckdns_rest GET "domains=$DuckDNS_domain&token=$DuckDNS_token&txt=$txtvalue" && [ $response == "OK" ]; then
    _info "TXT record has been successfully added to your DuckDNS domain."
    _info "Note that all subdomains under this domain uses the same TXT record."
    return 0
  else
    _err "Errors happened during adding the TXT record."
    return 1
  fi
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_duckdns_rm() {
  fulldomain=$1
  txtvalue=$2

  # Now remove the TXT record from DuckDNS
  _info "Trying to from TXT record"
  if _duckdns_rest GET "domains=$DuckDNS_domain&token=$DuckDNS_token&txt=''&clear=true" && [ $response == "OK" ]; then
    _info "TXT record has been successfully removed from your DuckDNS domain."
    return 0
  else
    _err "Errors happened during removing the TXT record."
    return 1
  fi
}

####################  Private functions below ##################################

#Usage: method  URI  data
_duckdns_rest() {
  method=$1
  param="$2"
  _debug param "$param"
  url="$DuckDNS_API?$param"
  _debug url "$url"

  # DuckDNS uses GET to update domain info
  if [ $method == "GET" ]; then
    response="$(_get "$url")"
  else
    _err "Unsupported method"
    return 1
  fi

  _debug response "$response"
  return 0
}
