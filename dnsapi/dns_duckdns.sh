#!/usr/bin/env sh

#Created by RaidenII, to use DuckDNS's API to add/remove text records
#06/27/2017

# Currently only support single domain access
# Due to the fact that DuckDNS uses StartSSL as cert provider, --insecure must be used with acme.sh

DuckDNS_API="https://www.duckdns.org/update"
API_Params="domains=$DuckDNS_domain&token=$DuckDNS_token"

########  Public functions #####################

#Usage: dns_duckdns_add _acme-challenge.domain.duckdns.org "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_duckdns_add() {
  fulldomain=$1
  txtvalue=$2

  # We'll extract the domain/username from full domain
  DuckDNS_domain=$(printf "%s\n" "$fulldomain" | rev | cut -d \. -f 3 | rev)

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
  if _duckdns_rest GET "$API_Params&txt=$txtvalue" && [ "$response" -eq "OK" ]; then
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
  _info "Trying to remove TXT record"
  if _duckdns_rest GET "$API_Params&txt=&clear=true" && [ "$response" -eq "OK" ]; then
    _info "TXT record has been successfully removed from your DuckDNS domain."
    return 0
  else
    _err "Errors happened during removing the TXT record."
    return 1
  fi
}

####################  Private functions below ##################################

#Usage: method URI
_duckdns_rest() {
  method=$1
  param="$2"
  _debug param "$param"
  url="$DuckDNS_API?$param"
  _debug url "$url"

  # DuckDNS uses GET to update domain info
  if [ "$method" -eq "GET" ]; then
    response="$(_get "$url")"
  else
    _err "Unsupported method"
    return 1
  fi

  _debug response "$response"
  return 0
}
