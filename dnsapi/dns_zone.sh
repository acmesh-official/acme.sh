#!/usr/bin/env sh

# Zone.ee dns API
# https://help.zone.eu/kb/zoneid-api-v2/
# required ZONE_Username and ZONE_Key

ZONE_Api="https://api.zone.eu/v2"
########  Public functions #####################

#Usage: dns_zone_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_zone_add() {
  fulldomain=$1
  txtvalue=$2
  _info "Using zone.ee dns api"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"
  ZONE_Username="${ZONE_Username:-$(_readaccountconf_mutable ZONE_Username)}"
  ZONE_Key="${ZONE_Key:-$(_readaccountconf_mutable ZONE_Key)}"
  if [ -z "$ZONE_Username" ] || [ -z "$ZONE_Key" ]; then
    ZONE_Username=""
    ZONE_Key=""
    _err "Zone api key and username must be present."
    return 1
  fi
  _saveaccountconf_mutable ZONE_Username "$ZONE_Username"
  _saveaccountconf_mutable ZONE_Key "$ZONE_Key"
  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug "Adding txt record"

  if _zone_rest POST "dns/${_domain}/txt" "{\"name\": \"$fulldomain\", \"destination\": \"$txtvalue\"}"; then
    if printf -- "%s" "$response" | grep "$fulldomain" >/dev/null; then
      _info "Added, OK"
      return 0
    else
      _err "Adding txt record error."
      return 1
    fi
  else
    _err "Adding txt record error."
  fi
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_zone_rm() {
  fulldomain=$1
  txtvalue=$2
  _info "Using zone.ee dns api"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"
  ZONE_Username="${ZONE_Username:-$(_readaccountconf_mutable ZONE_Username)}"
  ZONE_Key="${ZONE_Key:-$(_readaccountconf_mutable ZONE_Key)}"
  if [ -z "$ZONE_Username" ] || [ -z "$ZONE_Key" ]; then
    ZONE_Username=""
    ZONE_Key=""
    _err "Zone api key and username must be present."
    return 1
  fi
  _saveaccountconf_mutable ZONE_Username "$ZONE_Username"
  _saveaccountconf_mutable ZONE_Key "$ZONE_Key"
  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug "Getting txt records"
  _debug _domain "$_domain"

  _zone_rest GET "dns/${_domain}/txt"

  if printf "%s" "$response" | grep \"error\" >/dev/null; then
    _err "Error"
    return 1
  fi

  count=$(printf "%s\n" "$response" | _egrep_o "\"name\":\"$fulldomain\"" | wc -l)
  _debug count "$count"
  if [ "$count" = "0" ]; then
    _info "Nothing to remove."
  else
    record_id=$(printf "%s\n" "$response" | _egrep_o "\"id\":\"[^\"]*\",\"resource_url\":\"[^\"]*\",\"name\":\"$fulldomain\"," | cut -d : -f2 | cut -d , -f1 | tr -d \" | _head_n 1)
    if [ -z "$record_id" ]; then
      _err "No id found to remove."
      return 1
    fi
    if ! _zone_rest DELETE "dns/${_domain}/txt/$record_id"; then
      _err "Record deleting error."
      return 1
    fi
    _info "Record deleted"
    return 0
  fi

}

####################  Private functions below ##################################

_zone_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"

  realm="$(printf "%s" "$ZONE_Username:$ZONE_Key" | _base64)"

  export _H1="Authorization: Basic $realm"
  export _H2="Content-Type: application/json"

  if [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$ZONE_Api/$ep" "" "$m")"
  else
    response="$(_get "$ZONE_Api/$ep")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}

_get_root() {
  domain=$1
  i=2
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      return 1
    fi
    if ! _zone_rest GET "dns/$h"; then
      return 1
    fi
    if _contains "$response" "\"identificator\":\"$h\"" >/dev/null; then
      _domain=$h
      return 0
    fi
    i=$(_math "$i" + 1)
  done
  return 0
}
