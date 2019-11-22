#!/usr/bin/env sh

#Application Key
#OVH_AK="sdfsdfsdfljlbjkljlkjsdfoiwje"
#
#Application Secret
#OVH_AS="sdfsafsdfsdfdsfsdfsa"
#
#Consumer Key
#OVH_CK="sdfsdfsdfsdfsdfdsf"

#OVH_END_POINT=ovh-eu

#'ovh-eu'
OVH_EU='https://eu.api.ovh.com/1.0'

#'ovh-ca':
OVH_CA='https://ca.api.ovh.com/1.0'

#'kimsufi-eu'
KSF_EU='https://eu.api.kimsufi.com/1.0'

#'kimsufi-ca'
KSF_CA='https://ca.api.kimsufi.com/1.0'

#'soyoustart-eu'
SYS_EU='https://eu.api.soyoustart.com/1.0'

#'soyoustart-ca'
SYS_CA='https://ca.api.soyoustart.com/1.0'

#'runabove-ca'
RAV_CA='https://api.runabove.com/1.0'

wiki="https://github.com/Neilpang/acme.sh/wiki/How-to-use-OVH-domain-api"

ovh_success="https://github.com/Neilpang/acme.sh/wiki/OVH-Success"

_ovh_get_api() {
  _ogaep="$1"

  case "${_ogaep}" in

    ovh-eu | ovheu)
      printf "%s" $OVH_EU
      return
      ;;
    ovh-ca | ovhca)
      printf "%s" $OVH_CA
      return
      ;;
    kimsufi-eu | kimsufieu)
      printf "%s" $KSF_EU
      return
      ;;
    kimsufi-ca | kimsufica)
      printf "%s" $KSF_CA
      return
      ;;
    soyoustart-eu | soyoustarteu)
      printf "%s" $SYS_EU
      return
      ;;
    soyoustart-ca | soyoustartca)
      printf "%s" $SYS_CA
      return
      ;;
    runabove-ca | runaboveca)
      printf "%s" $RAV_CA
      return
      ;;

    *)

      _err "Unknown parameter : $1"
      return 1
      ;;
  esac
}

_initAuth() {
  OVH_AK="${OVH_AK:-$(_readaccountconf_mutable OVH_AK)}"
  OVH_AS="${OVH_AS:-$(_readaccountconf_mutable OVH_AS)}"

  if [ -z "$OVH_AK" ] || [ -z "$OVH_AS" ]; then
    OVH_AK=""
    OVH_AS=""
    _err "You don't specify OVH application key and application secret yet."
    _err "Please create you key and try again."
    return 1
  fi

  if [ "$OVH_AK" != "$(_readaccountconf OVH_AK)" ]; then
    _info "It seems that your ovh key is changed, let's clear consumer key first."
    _clearaccountconf OVH_CK
  fi
  _saveaccountconf_mutable OVH_AK "$OVH_AK"
  _saveaccountconf_mutable OVH_AS "$OVH_AS"

  OVH_END_POINT="${OVH_END_POINT:-$(_readaccountconf_mutable OVH_END_POINT)}"
  if [ -z "$OVH_END_POINT" ]; then
    OVH_END_POINT="ovh-eu"
  fi
  _info "Using OVH endpoint: $OVH_END_POINT"
  if [ "$OVH_END_POINT" != "ovh-eu" ]; then
    _saveaccountconf_mutable OVH_END_POINT "$OVH_END_POINT"
  fi

  OVH_API="$(_ovh_get_api $OVH_END_POINT)"
  _debug OVH_API "$OVH_API"

  OVH_CK="${OVH_CK:-$(_readaccountconf_mutable OVH_CK)}"
  if [ -z "$OVH_CK" ]; then
    _info "OVH consumer key is empty, Let's get one:"
    if ! _ovh_authentication; then
      _err "Can not get consumer key."
    fi
    #return and wait for retry.
    return 1
  fi

  _info "Checking authentication"

  if ! _ovh_rest GET "domain" || _contains "$response" "INVALID_CREDENTIAL" || _contains "$response" "NOT_CREDENTIAL"; then
    _err "The consumer key is invalid: $OVH_CK"
    _err "Please retry to create a new one."
    _clearaccountconf OVH_CK
    return 1
  fi
  _info "Consumer key is ok."
  return 0
}

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_ovh_add() {
  fulldomain=$1
  txtvalue=$2

  if ! _initAuth; then
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
  if _ovh_rest POST "domain/zone/$_domain/record" "{\"fieldType\":\"TXT\",\"subDomain\":\"$_sub_domain\",\"target\":\"$txtvalue\",\"ttl\":60}"; then
    if _contains "$response" "$txtvalue"; then
      _ovh_rest POST "domain/zone/$_domain/refresh"
      _debug "Refresh:$response"
      _info "Added, sleep 10 seconds."
      _sleep 10
      return 0
    fi
  fi
  _err "Add txt record error."
  return 1

}

#fulldomain
dns_ovh_rm() {
  fulldomain=$1
  txtvalue=$2

  if ! _initAuth; then
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
  if ! _ovh_rest GET "domain/zone/$_domain/record?fieldType=TXT&subDomain=$_sub_domain"; then
    return 1
  fi

  for rid in $(echo "$response" | tr '][,' '   '); do
    _debug rid "$rid"
    if ! _ovh_rest GET "domain/zone/$_domain/record/$rid"; then
      return 1
    fi
    if _contains "$response" "\"target\":\"$txtvalue\""; then
      _debug "Found txt id:$rid"
      if ! _ovh_rest DELETE "domain/zone/$_domain/record/$rid"; then
        return 1
      fi
      return 0
    fi
  done

  return 1
}

####################  Private functions below ##################################

_ovh_authentication() {

  _H1="X-Ovh-Application: $OVH_AK"
  _H2="Content-type: application/json"
  _H3=""
  _H4=""

  _ovhdata='{"accessRules": [{"method": "GET","path": "/auth/time"},{"method": "GET","path": "/domain"},{"method": "GET","path": "/domain/zone/*"},{"method": "GET","path": "/domain/zone/*/record"},{"method": "POST","path": "/domain/zone/*/record"},{"method": "POST","path": "/domain/zone/*/refresh"},{"method": "PUT","path": "/domain/zone/*/record/*"},{"method": "DELETE","path": "/domain/zone/*/record/*"}],"redirection":"'$ovh_success'"}'

  response="$(_post "$_ovhdata" "$OVH_API/auth/credential")"
  _debug3 response "$response"
  validationUrl="$(echo "$response" | _egrep_o "validationUrl\":\"[^\"]*\"" | _egrep_o "http.*\"" | tr -d '"')"
  if [ -z "$validationUrl" ]; then
    _err "Unable to get validationUrl"
    return 1
  fi
  _debug validationUrl "$validationUrl"

  consumerKey="$(echo "$response" | _egrep_o "consumerKey\":\"[^\"]*\"" | cut -d : -f 2 | tr -d '"')"
  if [ -z "$consumerKey" ]; then
    _err "Unable to get consumerKey"
    return 1
  fi
  _secure_debug consumerKey "$consumerKey"

  OVH_CK="$consumerKey"
  _saveaccountconf OVH_CK "$OVH_CK"

  _info "Please open this link to do authentication: $(__green "$validationUrl")"

  _info "Here is a guide for you: $(__green "$wiki")"
  _info "Please retry after the authentication is done."

}

#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
_get_root() {
  domain=$1
  i=2
  p=1
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    if ! _ovh_rest GET "domain/zone/$h"; then
      return 1
    fi

    if ! _contains "$response" "This service does not exist" >/dev/null && ! _contains "$response" "NOT_GRANTED_CALL" >/dev/null; then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
      _domain="$h"
      return 0
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

_ovh_timestamp() {
  _H1=""
  _H2=""
  _H3=""
  _H4=""
  _H5=""
  _get "$OVH_API/auth/time" "" 30
}

_ovh_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"

  _ovh_url="$OVH_API/$ep"
  _debug2 _ovh_url "$_ovh_url"
  _ovh_t="$(_ovh_timestamp)"
  _debug2 _ovh_t "$_ovh_t"
  _ovh_p="$OVH_AS+$OVH_CK+$m+$_ovh_url+$data+$_ovh_t"
  _secure_debug _ovh_p "$_ovh_p"
  _ovh_hex="$(printf "%s" "$_ovh_p" | _digest sha1 hex)"
  _debug2 _ovh_hex "$_ovh_hex"

  export _H1="X-Ovh-Application: $OVH_AK"
  export _H2="X-Ovh-Signature: \$1\$$_ovh_hex"
  _debug2 _H2 "$_H2"
  export _H3="X-Ovh-Timestamp: $_ovh_t"
  export _H4="X-Ovh-Consumer: $OVH_CK"
  export _H5="Content-Type: application/json;charset=utf-8"
  if [ "$data" ] || [ "$m" = "POST" ] || [ "$m" = "PUT" ] || [ "$m" = "DELETE" ]; then
    _debug data "$data"
    response="$(_post "$data" "$_ovh_url" "" "$m")"
  else
    response="$(_get "$_ovh_url")"
  fi

  if [ "$?" != "0" ] || _contains "$response" "INVALID_CREDENTIAL"; then
    _err "error $response"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
