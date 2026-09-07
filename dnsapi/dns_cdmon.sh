#!/usr/bin/env sh
# shellcheck disable=SC2034

dns_cdmon_info='cdmon
Site: www.cdmon.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_cdmon
Options:
 CDMON_Key API Key
'

CDMON_Api="https://api-domains.cdmon.services/api-domains"

########  Public functions #####################
# Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
# Used to add txt record
dns_cdmon_add() {
  fulldomain=$1
  txtvalue=$2

  CDMON_Key="${CDMON_Key:-$(_readaccountconf_mutable CDMON_Key)}"

  if [ -z "$CDMON_Key" ]; then
    CDMON_Key=""
    _err "You didn't specify your cdmon api key yet."
    _err "Please create your key and try again."
    return 1
  fi

  _saveaccountconf_mutable CDMON_Key "$CDMON_Key"

  _debug "First, we detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"
  _info "Adding record"
  if _cdmon_rest "dnsrecords/create" "{\"data\":{\"type\":\"TXT\",\"domain\":\"$_domain\",\"value\":\"$txtvalue\",\"ttl\":120,\"host\":\"$_sub_domain\"}}"; then
    if _contains "$response" "\"status\":\"ok\""; then
      _info "Added, OK"
      return 0
    else
      _err "Add txt record error."
      return 1
    fi
  fi
  _err "Add txt record error."
  return 1
}

# Usage: fulldomain txtvalue
# Used to remove the txt record after validation
dns_cdmon_rm() {
  fulldomain=$1
  txtvalue=$2

  CDMON_Key="${CDMON_Key:-$(_readaccountconf_mutable CDMON_Key)}"
  _debug "First, we detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _info "Removing record"
  if _cdmon_rest "dnsrecords/delete" "{\"data\":{\"value\":\"$txtvalue\",\"type\":\"TXT\",\"domain\":\"$_domain\",\"host\":\"$_sub_domain\"}}"; then
    if _contains "$response" "\"status\":\"ok\""; then
      _info "Deleted, OK"
      return 0
    else
      _err "Delete txt record error."
      return 1
    fi
  fi
  _err "Delete txt record error."
  return 1
}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
_get_root() {
  domain=$1
  i=1
  p=1

  if ! _cdmon_rest "domains/list"; then
    return 1
  fi

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi
    if _contains "$response" "\"domain\":\"$h\""; then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-"$p")
      _domain=$h
      return 0
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

_cdmon_rest() {
  ep="$1"
  data="$2"
  _debug "$ep"

  key_trimmed=$(echo "$CDMON_Key" | tr -d '"')

  export _H1="Content-Type: application/json"
  export _H2="apikey: $key_trimmed"

  _debug data "$data"
  response="$(_post "$data" "$CDMON_Api/$ep")"
  _ret="$?"

  unset _H1 _H2

  if [ "$_ret" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
