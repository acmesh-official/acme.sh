#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_firestorm_info='Firestorm.ch
Site: firestorm.ch
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_firestorm
Options:
 FST_Key Customer ID
 FST_Secret API Secret
 FST_Url API URL. Optional. Default "https://api.firestorm.ch/acme-dns".
Issues: github.com/acmesh-official/acme.sh/issues/6839
Author: FireStorm GmbH
'

FST_Url_DEFAULT="https://api.firestorm.ch/acme-dns"

########  Public functions #####################

# Usage: dns_firestorm_add _acme-challenge.www.example.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_firestorm_add() {
  fulldomain=$1
  txtvalue=$2

  FST_Key="${FST_Key:-$(_readaccountconf_mutable FST_Key)}"
  FST_Secret="${FST_Secret:-$(_readaccountconf_mutable FST_Secret)}"
  FST_Url="${FST_Url:-$(_readaccountconf_mutable FST_Url)}"

  if [ -z "$FST_Key" ] || [ -z "$FST_Secret" ]; then
    _err "FST_Key and FST_Secret must be set"
    _err "Get your API credentials at https://admin.firestorm.ch"
    return 1
  fi

  FST_Url="${FST_Url:-$FST_Url_DEFAULT}"

  _saveaccountconf_mutable FST_Key "$FST_Key"
  _saveaccountconf_mutable FST_Secret "$FST_Secret"
  if [ "$FST_Url" != "$FST_Url_DEFAULT" ]; then
    _saveaccountconf_mutable FST_Url "$FST_Url"
  else
    _clearaccountconf_mutable FST_Url
  fi

  subdomain=$(printf "%s" "$fulldomain" | sed 's/^_acme-challenge\.//')

  _info "Adding TXT record for $fulldomain"
  _debug "Subdomain" "$subdomain"
  _debug "TXT value" "$txtvalue"

  body="{\"subdomain\":\"$(_json_safe "$subdomain")\",\"txt\":\"$(_json_safe "$txtvalue")\"}"

  response="$(_firestorm_api "update" "$body")"

  if _contains "$response" "$txtvalue"; then
    _info "TXT record added successfully"
    return 0
  fi

  _err "Failed to add TXT record: $response"
  return 1
}

# Usage: dns_firestorm_rm _acme-challenge.www.example.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_firestorm_rm() {
  fulldomain=$1
  txtvalue=$2

  FST_Key="${FST_Key:-$(_readaccountconf_mutable FST_Key)}"
  FST_Secret="${FST_Secret:-$(_readaccountconf_mutable FST_Secret)}"
  FST_Url="${FST_Url:-$(_readaccountconf_mutable FST_Url)}"
  FST_Url="${FST_Url:-$FST_Url_DEFAULT}"

  if [ -z "$FST_Key" ] || [ -z "$FST_Secret" ]; then
    _err "FST_Key and FST_Secret must be set"
    return 1
  fi

  subdomain=$(printf "%s" "$fulldomain" | sed 's/^_acme-challenge\.//')

  _info "Removing TXT record for $fulldomain"

  body="{\"subdomain\":\"$(_json_safe "$subdomain")\",\"txt\":\"$(_json_safe "$txtvalue")\"}"

  response="$(_firestorm_api "remove" "$body")"

  if _contains "$response" "removed"; then
    _info "TXT record removed"
    return 0
  fi

  _err "Failed to remove TXT record: $response"
  return 1
}

####################  Private functions below ##################################

# Escape special characters for safe JSON string interpolation
_json_safe() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

_firestorm_api() {
  action=$1
  data=$2

  export _H1="X-Api-User: $FST_Key"
  export _H2="X-Api-Key: $FST_Secret"
  export _H3="Content-Type: application/json"

  _post "$data" "$FST_Url/$action" "" "POST"
}
