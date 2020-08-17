#!/usr/bin/env sh

CONOHA_DNS_EP_PREFIX_REGEXP="https://dns-service\."

########  Public functions #####################

#Usage: dns_conoha_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_conoha_add() {
  fulldomain=$1
  txtvalue=$2
  _info "Using conoha"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  _debug "Check uesrname and password"
  CONOHA_Username="${CONOHA_Username:-$(_readaccountconf_mutable CONOHA_Username)}"
  CONOHA_Password="${CONOHA_Password:-$(_readaccountconf_mutable CONOHA_Password)}"
  CONOHA_TenantId="${CONOHA_TenantId:-$(_readaccountconf_mutable CONOHA_TenantId)}"
  CONOHA_IdentityServiceApi="${CONOHA_IdentityServiceApi:-$(_readaccountconf_mutable CONOHA_IdentityServiceApi)}"
  if [ -z "$CONOHA_Username" ] || [ -z "$CONOHA_Password" ] || [ -z "$CONOHA_TenantId" ] || [ -z "$CONOHA_IdentityServiceApi" ]; then
    CONOHA_Username=""
    CONOHA_Password=""
    CONOHA_TenantId=""
    CONOHA_IdentityServiceApi=""
    _err "You didn't specify a conoha api username and password yet."
    _err "Please create the user and try again."
    return 1
  fi

  _saveaccountconf_mutable CONOHA_Username "$CONOHA_Username"
  _saveaccountconf_mutable CONOHA_Password "$CONOHA_Password"
  _saveaccountconf_mutable CONOHA_TenantId "$CONOHA_TenantId"
  _saveaccountconf_mutable CONOHA_IdentityServiceApi "$CONOHA_IdentityServiceApi"

  if token="$(_conoha_get_accesstoken "$CONOHA_IdentityServiceApi/tokens" "$CONOHA_Username" "$CONOHA_Password" "$CONOHA_TenantId")"; then
    accesstoken="$(printf "%s" "$token" | sed -n 1p)"
    CONOHA_Api="$(printf "%s" "$token" | sed -n 2p)"
  else
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain" "$CONOHA_Api" "$accesstoken"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _info "Adding record"
  body="{\"type\":\"TXT\",\"name\":\"$fulldomain.\",\"data\":\"$txtvalue\",\"ttl\":60}"
  if _conoha_rest POST "$CONOHA_Api/v1/domains/$_domain_id/records" "$body" "$accesstoken"; then
    if _contains "$response" '"data":"'"$txtvalue"'"'; then
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

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_conoha_rm() {
  fulldomain=$1
  txtvalue=$2
  _info "Using conoha"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  _debug "Check uesrname and password"
  CONOHA_Username="${CONOHA_Username:-$(_readaccountconf_mutable CONOHA_Username)}"
  CONOHA_Password="${CONOHA_Password:-$(_readaccountconf_mutable CONOHA_Password)}"
  CONOHA_TenantId="${CONOHA_TenantId:-$(_readaccountconf_mutable CONOHA_TenantId)}"
  CONOHA_IdentityServiceApi="${CONOHA_IdentityServiceApi:-$(_readaccountconf_mutable CONOHA_IdentityServiceApi)}"
  if [ -z "$CONOHA_Username" ] || [ -z "$CONOHA_Password" ] || [ -z "$CONOHA_TenantId" ] || [ -z "$CONOHA_IdentityServiceApi" ]; then
    CONOHA_Username=""
    CONOHA_Password=""
    CONOHA_TenantId=""
    CONOHA_IdentityServiceApi=""
    _err "You didn't specify a conoha api username and password yet."
    _err "Please create the user and try again."
    return 1
  fi

  _saveaccountconf_mutable CONOHA_Username "$CONOHA_Username"
  _saveaccountconf_mutable CONOHA_Password "$CONOHA_Password"
  _saveaccountconf_mutable CONOHA_TenantId "$CONOHA_TenantId"
  _saveaccountconf_mutable CONOHA_IdentityServiceApi "$CONOHA_IdentityServiceApi"

  if token="$(_conoha_get_accesstoken "$CONOHA_IdentityServiceApi/tokens" "$CONOHA_Username" "$CONOHA_Password" "$CONOHA_TenantId")"; then
    accesstoken="$(printf "%s" "$token" | sed -n 1p)"
    CONOHA_Api="$(printf "%s" "$token" | sed -n 2p)"
  else
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain" "$CONOHA_Api" "$accesstoken"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting txt records"
  if ! _conoha_rest GET "$CONOHA_Api/v1/domains/$_domain_id/records" "" "$accesstoken"; then
    _err "Error"
    return 1
  fi

  record_id=$(printf "%s" "$response" | _egrep_o '{[^}]*}' |
    grep '"type":"TXT"' | grep "\"data\":\"$txtvalue\"" | _egrep_o "\"id\":\"[^\"]*\"" |
    _head_n 1 | cut -d : -f 2 | tr -d \")
  if [ -z "$record_id" ]; then
    _err "Can not get record id to remove."
    return 1
  fi
  _debug record_id "$record_id"

  _info "Removing the txt record"
  if ! _conoha_rest DELETE "$CONOHA_Api/v1/domains/$_domain_id/records/$record_id" "" "$accesstoken"; then
    _err "Delete record error."
    return 1
  fi

  return 0
}

####################  Private functions below ##################################

_conoha_rest() {
  m="$1"
  ep="$2"
  data="$3"
  accesstoken="$4"

  export _H1="Accept: application/json"
  export _H2="Content-Type: application/json"
  if [ -n "$accesstoken" ]; then
    export _H3="X-Auth-Token: $accesstoken"
  fi

  _debug "$ep"
  if [ "$m" != "GET" ]; then
    _secure_debug2 data "$data"
    response="$(_post "$data" "$ep" "" "$m")"
  else
    response="$(_get "$ep")"
  fi
  _ret="$?"
  _secure_debug2 response "$response"
  if [ "$_ret" != "0" ]; then
    _err "error $ep"
    return 1
  fi

  response="$(printf "%s" "$response" | _normalizeJson)"
  return 0
}

_conoha_get_accesstoken() {
  ep="$1"
  username="$2"
  password="$3"
  tenantId="$4"

  accesstoken="$(_readaccountconf_mutable conoha_accesstoken)"
  expires="$(_readaccountconf_mutable conoha_tokenvalidto)"
  CONOHA_Api="$(_readaccountconf_mutable conoha_dns_ep)"

  # can we reuse the access token?
  if [ -n "$accesstoken" ] && [ -n "$expires" ] && [ -n "$CONOHA_Api" ]; then
    utc_date="$(_utc_date | sed "s/ /T/")"
    if expr "$utc_date" "<" "$expires" >/dev/null; then
      # access token is still valid - reuse it
      _debug "reusing access token"
      printf "%s\n%s\n" "$accesstoken" "$CONOHA_Api"
      return 0
    else
      _debug "access token expired"
    fi
  fi
  _debug "getting new access token"

  body="$(printf '{"auth":{"passwordCredentials":{"username":"%s","password":"%s"},"tenantId":"%s"}}' "$username" "$password" "$tenantId")"
  if ! _conoha_rest POST "$ep" "$body" ""; then
    _err error "$response"
    return 1
  fi
  accesstoken=$(printf "%s" "$response" | _egrep_o "\"id\":\"[^\"]*\"" | _head_n 1 | cut -d : -f 2 | tr -d \")
  expires=$(printf "%s" "$response" | _egrep_o "\"expires\":\"[^\"]*\"" | _head_n 1 | cut -d : -f 2-4 | tr -d \" | tr -d Z) #expect UTC
  if [ -z "$accesstoken" ] || [ -z "$expires" ]; then
    _err "no acccess token received. Check your Conoha settings see $WIKI"
    return 1
  fi
  _saveaccountconf_mutable conoha_accesstoken "$accesstoken"
  _saveaccountconf_mutable conoha_tokenvalidto "$expires"

  CONOHA_Api=$(printf "%s" "$response" | _egrep_o 'publicURL":"'"$CONOHA_DNS_EP_PREFIX_REGEXP"'[^"]*"' | _head_n 1 | cut -d : -f 2-3 | tr -d \")
  if [ -z "$CONOHA_Api" ]; then
    _err "failed to get conoha dns endpoint url"
    return 1
  fi
  _saveaccountconf_mutable conoha_dns_ep "$CONOHA_Api"

  printf "%s\n%s\n" "$accesstoken" "$CONOHA_Api"
  return 0
}

#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
# _domain_id=sdjkglgdfewsdfg
_get_root() {
  domain="$1"
  ep="$2"
  accesstoken="$3"
  i=2
  p=1
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100).
    _debug h "$h"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    if ! _conoha_rest GET "$ep/v1/domains?name=$h" "" "$accesstoken"; then
      return 1
    fi

    if _contains "$response" "\"name\":\"$h\"" >/dev/null; then
      _domain_id=$(printf "%s\n" "$response" | _egrep_o "\"id\":\"[^\"]*\"" | head -n 1 | cut -d : -f 2 | tr -d \")
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
