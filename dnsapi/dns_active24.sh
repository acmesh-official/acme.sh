#!/usr/bin/env sh

#ACTIVE24_Token="sdfsdfsdfljlbjkljlkjsdfoiwje"

ACTIVE24_Api="https://api.active24.com"

########  Public functions #####################

# Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
# Used to add txt record
dns_active24_add() {
  fulldomain=$1
  txtvalue=$2

  _active24_init

  _info "Adding txt record"
  if _active24_rest POST "dns/$_domain/txt/v1" "{\"name\":\"$_sub_domain\",\"text\":\"$txtvalue\",\"ttl\":0}"; then
    if _contains "$response" "errors"; then
      _err "Add txt record error."
      return 1
    else
      _info "Added, OK"
      return 0
    fi
  fi
  _err "Add txt record error."
  return 1
}

# Usage: fulldomain txtvalue
# Used to remove the txt record after validation
dns_active24_rm() {
  fulldomain=$1
  txtvalue=$2

  _active24_init

  _debug "Getting txt records"
  _active24_rest GET "dns/$_domain/records/v1"

  if _contains "$response" "errors"; then
    _err "Error"
    return 1
  fi

  hash_ids=$(echo "$response" | _egrep_o "[^{]+${txtvalue}[^}]+" | _egrep_o "hashId\":\"[^\"]+" | cut -c10-)

  for hash_id in $hash_ids; do
    _debug "Removing hash_id" "$hash_id"
    if _active24_rest DELETE "dns/$_domain/$hash_id/v1" ""; then
      if _contains "$response" "errors"; then
        _err "Unable to remove txt record."
        return 1
      else
        _info "Removed txt record."
        return 0
      fi
    fi
  done

  _err "No txt records found."
  return 1
}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
# _domain_id=sdjkglgdfewsdfg
_get_root() {
  domain=$1

  if ! _active24_rest GET "dns/domains/v1"; then
    return 1
  fi

  i=2
  p=1
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug "h" "$h"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    if _contains "$response" "\"$h\"" >/dev/null; then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
      _domain=$h
      return 0
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

_active24_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"

  export _H1="Authorization: Bearer $ACTIVE24_Token"

  if [ "$m" != "GET" ]; then
    _debug "data" "$data"
    response="$(_post "$data" "$ACTIVE24_Api/$ep" "" "$m" "application/json")"
  else
    response="$(_get "$ACTIVE24_Api/$ep")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}

_active24_init() {
  ACTIVE24_Token="${ACTIVE24_Token:-$(_readaccountconf_mutable ACTIVE24_Token)}"
  if [ -z "$ACTIVE24_Token" ]; then
    ACTIVE24_Token=""
    _err "You didn't specify a Active24 api token yet."
    _err "Please create the token and try again."
    return 1
  fi

  _saveaccountconf_mutable ACTIVE24_Token "$ACTIVE24_Token"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"
}
