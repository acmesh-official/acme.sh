#!/usr/bin/env sh

#
#NODION_API_KEY="abc123"
#

NODION_API_URL="https://api.nodion.com/p/v1"

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_nodion_add() {
  fulldomain=$1
  txtvalue=$2

  NODION_API_KEY="${NODION_API_KEY:-$(_readaccountconf_mutable NODION_API_KEY)}"

  if [ -z "$NODION_API_KEY" ]; then
    NODION_API_KEY=""
    _err "You didn't specify a NODION_API_KEY."
    _err "API keys can be created at https://app.nodion.com/user/security."
    _err "Please create your key and try again."
    return 1
  fi

  _saveaccountconf NODION_API_KEY "$NODION_API_KEY"

  _debug2 "Detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "Invalid domain"
    return 1
  fi
  _debug2 _domain_id "$_domain_id"
  _debug2 _sub_domain "$_sub_domain"
  _debug2 _domain "$_domain"

  #_debug "Getting txt records"
  #_nodion_rest GET "dns_zones/${_domain_id}/records?record_type=txt&name=$_sub_domain"

  _info "Adding record"
  if _nodion_rest POST "dns_zones/$_domain_id/records" "{\"record_type\":\"txt\",\"name\":\"$_sub_domain\",\"content\":\"$txtvalue\",\"ttl\":120}"; then
    if _contains "$response" "$txtvalue"; then
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

#fulldomain txtvalue
dns_nodion_rm() {
  fulldomain=$1
  txtvalue=$2

  _debug2 "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug2 _domain_id "$_domain_id"
  _debug2 _sub_domain "$_sub_domain"
  _debug2 _domain "$_domain"

  _debug "Getting txt records"
  _nodion_rest GET "dns_zones/${_domain_id}/records?record_type=txt&name=$_sub_domain&content=$txtvalue"

  if _contains "$response" "\"content\":\"$txtvalue\""; then
    record_id=$(echo "$response" | _egrep_o "\[.\"id\": *\"[^\"]*\"" | _head_n 1 | cut -d : -f 2 | tr -d \" | tr -d " ")
    _debug2 "record_id" "$record_id"
    if [ "$record_id" ]; then
      if ! _nodion_rest DELETE "dns_zones/$_domain_id/records/$record_id"; then
        _err "Delete record error."
        return 1
      fi
    else
      _err "Record ID could not be fetched."
      return 1
    fi
  else
    _err "Record not found by content."
    return 1
  fi

}

####################  Private functions below ##################################
#  https://github.com/acmesh-official/acme.sh/wiki/DNS-API-Dev-Guide
#  The following full domains are possible:
#  _acme-challenge.www.example.com
#  _acme-challenge.example.com
#  _acme-challenge.example.co.uk
#  _acme-challenge.www.example.co.uk
#  _acme-challenge.sub1.sub2.www.example.co.uk
#  sub1.sub2.example.co.uk
#  example.com ( For dns alias mode)
#  example.co.uk ( For dns alias mode)
#
#  We need to split it to get the following:
#  _sub_domain=_acme-challenge.www
#  _domain=example.com
#  _domain_id=uuid

_get_root() {
  # The goal is to split the domain to get the actual domain name, as well as sub_domain and an id to send API requests to
  domain=$1
  i=1
  p=1

  while true; do
    echo $i
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug h "$h"

    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    if ! _nodion_rest GET "dns_zones?name=$h"; then
      return 1
    fi

    if _contains "$response" "\"name\":\"$h\""; then
      _domain_id=$(echo "$response" | _egrep_o "\[.\"id\": *\"[^\"]*\"" | _head_n 1 | cut -d : -f 2 | tr -d \" | tr -d " ")
      if [ "$_domain_id" ]; then
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

_nodion_rest() {
  method=$1
  path="$2"
  data="$3"

  token_trimmed=$(echo "$NODION_API_KEY" | tr -d '"')

  export _H1="Accept: application/json"
  export _H2="Content-Type: application/json"
  export _H3="Authorization: $token_trimmed"

  if [ "$method" != "GET" ]; then
    response="$(_post "$data" "$NODION_API_URL/$path" "" "$method")"
  else
    response="$(_get "$NODION_API_URL/$path")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $path"
    return 1
  fi

  return 0
}
