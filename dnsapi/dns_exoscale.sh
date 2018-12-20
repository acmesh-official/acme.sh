#!/usr/bin/env sh

EXOSCALE_API=https://api.exoscale.com/dns/v1

########  Public functions #####################

# Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
# Used to add txt record
dns_exoscale_add() {
  fulldomain=$1
  txtvalue=$2

  if ! _checkAuth; then
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
  if _exoscale_rest POST "domains/$_domain_id/records" "{\"record\":{\"name\":\"$_sub_domain\",\"record_type\":\"TXT\",\"content\":\"$txtvalue\",\"ttl\":120}}" "$_domain_token"; then
    if _contains "$response" "$txtvalue"; then
      _info "Added, OK"
      return 0
    fi
  fi
  _err "Add txt record error."
  return 1

}

# Usage: fulldomain txtvalue
# Used to remove the txt record after validation
dns_exoscale_rm() {
  fulldomain=$1
  txtvalue=$2

  if ! _checkAuth; then
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting txt records"
  _exoscale_rest GET "domains/${_domain_id}/records?type=TXT&name=$_sub_domain" "" "$_domain_token"
  if _contains "$response" "\"name\":\"$_sub_domain\"" >/dev/null; then
    _record_id=$(echo "$response" | tr '{' "\n" | grep "\"content\":\"$txtvalue\"" | _egrep_o "\"id\":[^,]+" | _head_n 1 | cut -d : -f 2 | tr -d \")
  fi

  if [ -z "$_record_id" ]; then
    _err "Can not get record id to remove."
    return 1
  fi

  _debug "Deleting record $_record_id"

  if ! _exoscale_rest DELETE "domains/$_domain_id/records/$_record_id" "" "$_domain_token"; then
    _err "Delete record error."
    return 1
  fi

  return 0
}

####################  Private functions below ##################################

_checkAuth() {
  EXOSCALE_API_KEY="${EXOSCALE_API_KEY:-$(_readaccountconf_mutable EXOSCALE_API_KEY)}"
  EXOSCALE_SECRET_KEY="${EXOSCALE_SECRET_KEY:-$(_readaccountconf_mutable EXOSCALE_SECRET_KEY)}"

  if [ -z "$EXOSCALE_API_KEY" ] || [ -z "$EXOSCALE_SECRET_KEY" ]; then
    EXOSCALE_API_KEY=""
    EXOSCALE_SECRET_KEY=""
    _err "You don't specify Exoscale application key and application secret yet."
    _err "Please create you key and try again."
    return 1
  fi

  _saveaccountconf_mutable EXOSCALE_API_KEY "$EXOSCALE_API_KEY"
  _saveaccountconf_mutable EXOSCALE_SECRET_KEY "$EXOSCALE_SECRET_KEY"

  return 0
}

#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
# _domain_id=sdjkglgdfewsdfg
# _domain_token=sdjkglgdfewsdfg
_get_root() {

  if ! _exoscale_rest GET "domains"; then
    return 1
  fi

  domain=$1
  i=2
  p=1
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    if _contains "$response" "\"name\":\"$h\"" >/dev/null; then
      _domain_id=$(echo "$response" | tr '{' "\n" | grep "\"name\":\"$h\"" | _egrep_o "\"id\":[^,]+" | _head_n 1 | cut -d : -f 2 | tr -d \")
      _domain_token=$(echo "$response" | tr '{' "\n" | grep "\"name\":\"$h\"" | _egrep_o "\"token\":\"[^\"]*\"" | _head_n 1 | cut -d : -f 2 | tr -d \")
      if [ "$_domain_token" ] && [ "$_domain_id" ]; then
        _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
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

# returns response
_exoscale_rest() {
  method=$1
  path="$2"
  data="$3"
  token="$4"
  request_url="$EXOSCALE_API/$path"
  _debug "$path"

  export _H1="Accept: application/json"

  if [ "$token" ]; then
    export _H2="X-DNS-Domain-Token: $token"
  else
    export _H2="X-DNS-Token: $EXOSCALE_API_KEY:$EXOSCALE_SECRET_KEY"
  fi

  if [ "$data" ] || [ "$method" = "DELETE" ]; then
    export _H3="Content-Type: application/json"
    _debug data "$data"
    response="$(_post "$data" "$request_url" "" "$method")"
  else
    response="$(_get "$request_url" "" "" "$method")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $request_url"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
