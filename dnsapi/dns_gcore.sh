#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_gcore_info='Gcore.com
Site: Gcore.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_gcore
Options:
 GCORE_Key API Key
Issues: github.com/acmesh-official/acme.sh/issues/4460
'

GCORE_Api="https://api.gcore.com/dns/v2"
GCORE_Doc="https://api.gcore.com/docs/dns"

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_gcore_add() {
  fulldomain=$1
  txtvalue=$2

  GCORE_Key="${GCORE_Key:-$(_readaccountconf_mutable GCORE_Key)}"

  if [ -z "$GCORE_Key" ]; then
    GCORE_Key=""
    _err "You didn't specify a Gcore api key yet."
    _err "You can get yours from here $GCORE_Doc"
    return 1
  fi

  #save the api key to the account conf file.
  _saveaccountconf_mutable GCORE_Key "$GCORE_Key" "base64"

  _debug "First detect the zone name"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _zone_name "$_zone_name"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting txt records"
  _gcore_rest GET "zones/$_zone_name/$fulldomain/TXT"
  payload=""

  if echo "$response" | grep "record is not found" >/dev/null; then
    _info "Record doesn't exists"
    payload="{\"resource_records\":[{\"content\":[\"$txtvalue\"],\"enabled\":true}],\"ttl\":120}"
  elif echo "$response" | grep "$txtvalue" >/dev/null; then
    _info "Already exists, OK"
    return 0
  elif echo "$response" | tr -d " " | grep \"name\":\""$fulldomain"\",\"type\":\"TXT\" >/dev/null; then
    _info "Record with mismatch txtvalue, try update it"
    payload=$(echo "$response" | tr -d " " | sed 's/"updated_at":[0-9]\+,//g' | sed 's/"meta":{}}]}/"meta":{}},{"content":['\""$txtvalue"\"'],"enabled":true}]}/')
  fi

  # For wildcard cert, the main root domain and the wildcard domain have the same txt subdomain name, so
  # we can not use updating anymore.
  #  count=$(printf "%s\n" "$response" | _egrep_o "\"count\":[^,]*" | cut -d : -f 2)
  #  _debug count "$count"
  #  if [ "$count" = "0" ]; then
  _info "Adding record"
  if _gcore_rest PUT "zones/$_zone_name/$fulldomain/TXT" "$payload"; then
    if _contains "$response" "$txtvalue"; then
      _info "Added, OK"
      return 0
    elif _contains "$response" "rrset is already exists"; then
      _info "Already exists, OK"
      return 0
    else
      _err "Add txt record error."
      return 1
    fi
  fi
  _err "Add txt record error."
  return 1
}

#fulldomain txtvalue
dns_gcore_rm() {
  fulldomain=$1
  txtvalue=$2

  GCORE_Key="${GCORE_Key:-$(_readaccountconf_mutable GCORE_Key)}"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _zone_name "$_zone_name"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting txt records"
  _gcore_rest GET "zones/$_zone_name/$fulldomain/TXT"

  if echo "$response" | grep "record is not found" >/dev/null; then
    _info "No such txt recrod"
    return 0
  fi

  if ! echo "$response" | tr -d " " | grep \"name\":\""$fulldomain"\",\"type\":\"TXT\" >/dev/null; then
    _err "Error: $response"
    return 1
  fi

  if ! echo "$response" | tr -d " " | grep \""$txtvalue"\" >/dev/null; then
    _info "No such txt recrod"
    return 0
  fi

  count="$(echo "$response" | grep -o "content" | wc -l)"

  if [ "$count" = "1" ]; then
    if ! _gcore_rest DELETE "zones/$_zone_name/$fulldomain/TXT"; then
      _err "Delete record error. $response"
      return 1
    fi
    return 0
  fi

  payload="$(echo "$response" | tr -d " " | sed 's/"updated_at":[0-9]\+,//g' | sed 's/{"id":[0-9]\+,"content":\["'"$txtvalue"'"\],"enabled":true,"meta":{}}//' | sed 's/\[,/\[/' | sed 's/,,/,/' | sed 's/,\]/\]/')"
  if ! _gcore_rest PUT "zones/$_zone_name/$fulldomain/TXT" "$payload"; then
    _err "Delete record error. $response"
  fi
}

####################  Private functions below ##################################
#_acme-challenge.sub.domain.com
#returns
# _sub_domain=_acme-challenge.sub or _acme-challenge
# _domain=domain.com
# _zone_name=domain.com or sub.domain.com
_get_root() {
  domain=$1
  i=1
  p=1

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    if ! _gcore_rest GET "zones/$h"; then
      return 1
    fi

    if _contains "$response" "\"name\":\"$h\""; then
      _zone_name=$h
      if [ "$_zone_name" ]; then
        _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-"$p")
        _domain=$h
        return 0
      fi
      return 1
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

_gcore_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"

  key_trimmed=$(echo "$GCORE_Key" | tr -d '"')

  export _H1="Content-Type: application/json"
  export _H2="Authorization: APIKey $key_trimmed"

  if [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$GCORE_Api/$ep" "" "$m")"
  else
    response="$(_get "$GCORE_Api/$ep")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
