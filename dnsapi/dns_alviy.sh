#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_alviy_info='Alviy.com
Site: Alviy.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_alviy
Options:
 Alviy_token API token. Get it from the https://cloud.alviy.com/token
Issues: github.com/acmesh-official/acme.sh/issues/5115
'

Alviy_Api="https://cloud.alviy.com/api/v1"

########  Public functions #####################

#Usage: dns_alviy_add  _acme-challenge.www.domain.com   "content"
dns_alviy_add() {
  fulldomain=$1
  txtvalue=$2

  Alviy_token="${Alviy_token:-$(_readaccountconf_mutable Alviy_token)}"
  if [ -z "$Alviy_token" ]; then
    Alviy_token=""
    _err "Please specify Alviy token."
    return 1
  fi

  #save the api key and email to the account conf file.
  _saveaccountconf_mutable Alviy_token "$Alviy_token"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting existing records"
  if _alviy_txt_exists "$_domain" "$fulldomain" "$txtvalue"; then
    _info "This record already exists, skipping"
    return 0
  fi

  _add_data="{\"content\":\"$txtvalue\",\"type\":\"TXT\"}"
  _debug2 _add_data "$_add_data"
  _info "Adding record"
  if _alviy_rest POST "zone/$_domain/domain/$fulldomain/" "$_add_data"; then
    _debug "Checking updated records of '${fulldomain}'"

    if ! _alviy_txt_exists "$_domain" "$fulldomain" "$txtvalue"; then
      _err "TXT record '${txtvalue}' for '${fulldomain}', value wasn't set!"
      return 1
    fi

  else
    _err "Add txt record error, value '${txtvalue}' for '${fulldomain}' was not set."
    return 1
  fi

  _sleep 10
  _info "Added TXT record '${txtvalue}' for '${fulldomain}'."
  return 0
}

#fulldomain
dns_alviy_rm() {
  fulldomain=$1
  txtvalue=$2

  Alviy_token="${Alviy_token:-$(_readaccountconf_mutable Alviy_token)}"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  if ! _alviy_txt_exists "$_domain" "$fulldomain" "$txtvalue"; then
    _info "The record does not exist, skip"
    return 0
  fi

  _add_data=""
  uuid=$(echo "$response" | tr "{" "\n" | grep "$txtvalue" | tr "," "\n" | grep uuid | cut -d \" -f4)
  # delete record
  _debug "Delete TXT record for '${fulldomain}'"
  if ! _alviy_rest DELETE "zone/$_domain/record/$uuid" "{\"confirm\":1}"; then
    _err "Cannot delete empty TXT record for '$fulldomain'"
    return 1
  fi
  _info "The record '$fulldomain'='$txtvalue' deleted"
}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
_get_root() {
  domain=$1
  i=3
  a="init"
  while [ -n "$a" ]; do
    a=$(printf "%s" "$domain" | cut -d . -f $i-)
    i=$((i + 1))
  done
  n=$((i - 3))
  h=$(printf "%s" "$domain" | cut -d . -f $n-)
  if [ -z "$h" ]; then
    #not valid
    _alviy_rest GET "zone/$domain/"
    _debug "can't get host from $domain"
    return 1
  fi

  if ! _alviy_rest GET "zone/$h/"; then
    return 1
  fi

  if _contains "$response" '"code":"NOT_FOUND"'; then
    _debug "$h not found"
  else
    s=$((n - 1))
    _sub_domain=$(printf "%s" "$domain" | cut -d . -f -$s)
    _domain="$h"
    return 0
  fi
  return 1
}

_alviy_txt_exists() {
  zone=$1
  domain=$2
  content_data=$3
  _debug "Getting existing records"

  if ! _alviy_rest GET "zone/$zone/domain/$domain/TXT/"; then
    _info "The record does not exist"
    return 1
  fi

  if ! _contains "$response" "$3"; then
    _info "The record has other value"
    return 1
  fi
  # GOOD code return - TRUE function
  return 0
}

_alviy_rest() {
  method=$1
  path="$2"
  content_data="$3"
  _debug "$path"

  export _H1="Authorization: Bearer $Alviy_token"
  export _H2="Content-Type: application/json"

  if [ "$content_data" ] || [ "$method" = "DELETE" ]; then
    _debug "data ($method): " "$content_data"
    response="$(_post "$content_data" "$Alviy_Api/$path" "" "$method")"
  else
    response="$(_get "$Alviy_Api/$path")"
  fi
  _code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\\r\\n")"
  if [ "$_code" = "401" ]; then
    _err "It seems that your api key or secret is not correct."
    return 1
  fi

  if [ "$_code" != "200" ]; then
    _err "API call error ($method): $path Response code $_code"
  fi
  if [ "$?" != "0" ]; then
    _err "error on rest call ($method): $path. Response:"
    _err "$response"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
