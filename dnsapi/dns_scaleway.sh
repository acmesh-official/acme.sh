#!/usr/bin/env sh

# Scaleway API
# https://developers.scaleway.com/en/products/domain/dns/api/
#
# Requires Scaleway API token set in SCALEWAY_API_TOKEN

########  Public functions #####################

SCALEWAY_API="https://api.scaleway.com/domain/v2beta1"

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_scaleway_add() {
  fulldomain=$1
  txtvalue=$2

  if ! _scaleway_check_config; then
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _info "Adding record"
  _scaleway_create_TXT_record "$_domain" "$_sub_domain" "$txtvalue"
  if _contains "$response" "records"; then
    return 0
  else
    _err error "$response"
    return 1
  fi
  _info "Record added."

  return 0
}

dns_scaleway_rm() {
  fulldomain=$1
  txtvalue=$2

  if ! _scaleway_check_config; then
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _info "Deleting record"
  _scaleway_delete_TXT_record "$_domain" "$_sub_domain" "$txtvalue"
  if _contains "$response" "records"; then
    return 0
  else
    _err error "$response"
    return 1
  fi
  _info "Record deleted."

  return 0
}

####################  Private functions below ##################################

_scaleway_check_config() {
  SCALEWAY_API_TOKEN="${SCALEWAY_API_TOKEN:-$(_readaccountconf_mutable SCALEWAY_API_TOKEN)}"
  if [ -z "$SCALEWAY_API_TOKEN" ]; then
    _err "No API key specified for Scaleway API."
    _err "Create your key and export it as SCALEWAY_API_TOKEN"
    return 1
  fi
  if ! _scaleway_rest GET "dns-zones"; then
    _err "Invalid API key specified for Scaleway API."
    return 1
  fi

  _saveaccountconf_mutable SCALEWAY_API_TOKEN "$SCALEWAY_API_TOKEN"

  return 0
}

#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
_get_root() {
  domain=$1
  i=1
  p=1
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    _scaleway_rest GET "dns-zones/$h/records"

    if ! _contains "$response" "subdomain not found" >/dev/null; then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
      _domain="$h"
      return 0
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  _err "Unable to retrive DNS zone matching this domain"
  return 1
}

# this function add a TXT record
_scaleway_create_TXT_record() {
  txt_zone=$1
  txt_name=$2
  txt_value=$3

  _scaleway_rest PATCH "dns-zones/$txt_zone/records" "{\"return_all_records\":false,\"changes\":[{\"add\":{\"records\":[{\"name\":\"$txt_name\",\"data\":\"$txt_value\",\"type\":\"TXT\",\"ttl\":60}]}}]}"

  if _contains "$response" "records"; then
    return 0
  else
    _err "error1 $response"
    return 1
  fi
}

# this function delete a TXT record based on name and content
_scaleway_delete_TXT_record() {
  txt_zone=$1
  txt_name=$2
  txt_value=$3

  _scaleway_rest PATCH "dns-zones/$txt_zone/records" "{\"return_all_records\":false,\"changes\":[{\"delete\":{\"id_fields\":{\"name\":\"$txt_name\",\"data\":\"$txt_value\",\"type\":\"TXT\"}}}]}"

  if _contains "$response" "records"; then
    return 0
  else
    _err "error2 $response"
    return 1
  fi
}

_scaleway_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"
  _scaleway_url="$SCALEWAY_API/$ep"
  _debug2 _scaleway_url "$_scaleway_url"
  export _H1="x-auth-token: $SCALEWAY_API_TOKEN"
  export _H2="Accept: application/json"
  export _H3="Content-Type: application/json"

  if [ "$data" ] || [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$_scaleway_url" "" "$m")"
  else
    response="$(_get "$_scaleway_url")"
  fi
  if [ "$?" != "0" ] || _contains "$response" "denied_authentication" || _contains "$response" "Method not allowed" || _contains "$response" "json parse error: unexpected EOF"; then
    _err "error $response"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
