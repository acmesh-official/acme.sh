#!/usr/bin/env sh

#Created by RaidenII, to use DuckDNS's API to add/remove text records
#06/27/2017

# Pass credentials before "acme.sh --issue --dns dns_duckdns ..."
# --
# export DuckDNS_Token="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
# --
#
# Due to the fact that DuckDNS uses StartSSL as cert provider, --insecure may need to be used with acme.sh

DuckDNS_API="https://www.duckdns.org/update"

########  Public functions #####################

#Usage: dns_duckdns_add _acme-challenge.domain.duckdns.org "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_duckdns_add() {
  fulldomain=$1
  txtvalue=$2

  DuckDNS_Token="${DuckDNS_Token:-$(_readaccountconf_mutable DuckDNS_Token)}"
  if [ -z "$DuckDNS_Token" ]; then
    _err "You must export variable: DuckDNS_Token"
    _err "The token for your DuckDNS account is necessary."
    _err "You can look it up in your DuckDNS account."
    return 1
  fi

  # Now save the credentials.
  _saveaccountconf_mutable DuckDNS_Token "$DuckDNS_Token"

  # Unfortunately, DuckDNS does not seems to support lookup domain through API
  # So I assume your credentials (which are your domain and token) are correct
  # If something goes wrong, we will get a KO response from DuckDNS

  if ! _duckdns_get_domain; then
    return 1
  fi

  # Now add the TXT record to DuckDNS
  _info "Trying to add TXT record"
  if _duckdns_rest GET "domains=$_duckdns_domain&token=$DuckDNS_Token&txt=$txtvalue"; then
    if [ "$response" = "OK" ]; then
      _info "TXT record has been successfully added to your DuckDNS domain."
      _info "Note that all subdomains under this domain uses the same TXT record."
      return 0
    else
      _err "Errors happened during adding the TXT record, response=$response"
      return 1
    fi
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

  DuckDNS_Token="${DuckDNS_Token:-$(_readaccountconf_mutable DuckDNS_Token)}"
  if [ -z "$DuckDNS_Token" ]; then
    _err "You must export variable: DuckDNS_Token"
    _err "The token for your DuckDNS account is necessary."
    _err "You can look it up in your DuckDNS account."
    return 1
  fi

  if ! _duckdns_get_domain; then
    return 1
  fi

  # Now remove the TXT record from DuckDNS
  _info "Trying to remove TXT record"
  if _duckdns_rest GET "domains=$_duckdns_domain&token=$DuckDNS_Token&txt=&clear=true"; then
    if [ "$response" = "OK" ]; then
      _info "TXT record has been successfully removed from your DuckDNS domain."
      return 0
    else
      _err "Errors happened during removing the TXT record, response=$response"
      return 1
    fi
  else
    _err "Errors happened during removing the TXT record."
    return 1
  fi
}

####################  Private functions below ##################################

#fulldomain=_acme-challenge.domain.duckdns.org
#returns
# _duckdns_domain=domain
_duckdns_get_domain() {

  # We'll extract the domain/username from full domain
  _duckdns_domain="$(printf "%s" "$fulldomain" | _lower_case | _egrep_o '[.][^.][^.]*[.]duckdns.org' | cut -d . -f 2)"

  if [ -z "$_duckdns_domain" ]; then
    _err "Error extracting the domain."
    return 1
  fi

  return 0
}

#Usage: method URI
_duckdns_rest() {
  method=$1
  param="$2"
  _debug param "$param"
  url="$DuckDNS_API?$param"
  _debug url "$url"

  # DuckDNS uses GET to update domain info
  if [ "$method" = "GET" ]; then
    response="$(_get "$url")"
  else
    _err "Unsupported method"
    return 1
  fi

  _debug2 response "$response"
  return 0
}
