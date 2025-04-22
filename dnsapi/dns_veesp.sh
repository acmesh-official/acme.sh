#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_veesp_info='veesp.com
Site: veesp.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_veesp
Options:
 VEESP_User Username
 VEESP_Password Password
Issues: github.com/acmesh-official/acme.sh/issues/3712
Author: <stepan@plyask.in>
'

VEESP_Api="https://secure.veesp.com/api"

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_veesp_add() {
  fulldomain=$1
  txtvalue=$2

  VEESP_Password="${VEESP_Password:-$(_readaccountconf_mutable VEESP_Password)}"
  VEESP_User="${VEESP_User:-$(_readaccountconf_mutable VEESP_User)}"
  VEESP_auth=$(printf "%s" "$VEESP_User:$VEESP_Password" | _base64)

  if [ -z "$VEESP_Password" ] || [ -z "$VEESP_User" ]; then
    VEESP_Password=""
    VEESP_User=""
    _err "You don't specify veesp api key and email yet."
    _err "Please create you key and try again."
    return 1
  fi

  #save the api key and email to the account conf file.
  _saveaccountconf_mutable VEESP_Password "$VEESP_Password"
  _saveaccountconf_mutable VEESP_User "$VEESP_User"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _info "Adding record"
  if VEESP_rest POST "service/$_service_id/dns/$_domain_id/records" "{\"name\":\"$fulldomain\",\"ttl\":1,\"priority\":0,\"type\":\"TXT\",\"content\":\"$txtvalue\"}"; then
    if _contains "$response" "\"success\":true"; then
      _info "Added"
      #todo: check if the record takes effect
      return 0
    else
      _err "Add txt record error."
      return 1
    fi
  fi
}

# Usage: fulldomain txtvalue
# Used to remove the txt record after validation
dns_veesp_rm() {
  fulldomain=$1
  txtvalue=$2

  VEESP_Password="${VEESP_Password:-$(_readaccountconf_mutable VEESP_Password)}"
  VEESP_User="${VEESP_User:-$(_readaccountconf_mutable VEESP_User)}"
  VEESP_auth=$(printf "%s" "$VEESP_User:$VEESP_Password" | _base64)

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting txt records"
  VEESP_rest GET "service/$_service_id/dns/$_domain_id"

  count=$(printf "%s\n" "$response" | _egrep_o "\"type\":\"TXT\",\"content\":\".\"$txtvalue.\"\"" | wc -l | tr -d " ")
  _debug count "$count"
  if [ "$count" = "0" ]; then
    _info "Don't need to remove."
  else
    record_id=$(printf "%s\n" "$response" | _egrep_o "{\"id\":[^}]*\"type\":\"TXT\",\"content\":\".\"$txtvalue.\"\"" | cut -d\" -f4)
    _debug "record_id" "$record_id"
    if [ -z "$record_id" ]; then
      _err "Can not get record id to remove."
      return 1
    fi
    if ! VEESP_rest DELETE "service/$_service_id/dns/$_domain_id/records/$record_id"; then
      _err "Delete record error."
      return 1
    fi
    _contains "$response" "\"success\":true"
  fi
}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
# _domain_id=sdjkglgdfewsdfg
_get_root() {
  domain=$1
  i=2
  p=1
  if ! VEESP_rest GET "dns"; then
    return 1
  fi
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    if _contains "$response" "\"name\":\"$h\""; then
      _domain_id=$(printf "%s\n" "$response" | _egrep_o "\"domain_id\":[^,]*,\"name\":\"$h\"" | cut -d : -f 2 | cut -d , -f 1 | cut -d '"' -f 2)
      _debug _domain_id "$_domain_id"
      _service_id=$(printf "%s\n" "$response" | _egrep_o "\"name\":\"$h\",\"service_id\":[^}]*" | cut -d : -f 3 | cut -d '"' -f 2)
      _debug _service_id "$_service_id"
      if [ "$_domain_id" ]; then
        _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-"$p")
        _domain="$h"
        return 0
      fi
      return 1
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

VEESP_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"

  export _H1="Accept: application/json"
  export _H2="Authorization: Basic $VEESP_auth"
  if [ "$m" != "GET" ]; then
    _debug data "$data"
    export _H3="Content-Type: application/json"
    response="$(_post "$data" "$VEESP_Api/$ep" "" "$m")"
  else
    response="$(_get "$VEESP_Api/$ep")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
