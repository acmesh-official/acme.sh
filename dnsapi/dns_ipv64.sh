#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_ipv64_info='IPv64.net
Site: IPv64.net
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_ipv64
Options:
 IPv64_Token API Token
Issues: github.com/acmesh-official/acme.sh/issues/4419
Author: Roman Lumetsberger
'

IPv64_API="https://ipv64.net/api"

########  Public functions ######################

#Usage: dns_ipv64_add _acme-challenge.domain.ipv64.net "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_ipv64_add() {
  fulldomain=$1
  txtvalue=$2

  IPv64_Token="${IPv64_Token:-$(_readaccountconf_mutable IPv64_Token)}"
  if [ -z "$IPv64_Token" ]; then
    _err "You must export variable: IPv64_Token"
    _err "The API Key for your IPv64 account is necessary."
    _err "You can look it up in your IPv64 account."
    return 1
  fi

  # Now save the credentials.
  _saveaccountconf_mutable IPv64_Token "$IPv64_Token"

  if ! _get_root "$fulldomain"; then
    _err "invalid domain" "$fulldomain"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  # convert to lower case
  _domain="$(echo "$_domain" | _lower_case)"
  _sub_domain="$(echo "$_sub_domain" | _lower_case)"
  # Now add the TXT record
  _info "Trying to add TXT record"
  if _ipv64_rest "POST" "add_record=$_domain&praefix=$_sub_domain&type=TXT&content=$txtvalue"; then
    _info "TXT record has been successfully added."
    return 0
  else
    _err "Errors happened during adding the TXT record, response=$_response"
    return 1
  fi

}

#Usage: fulldomain txtvalue
#Usage: dns_ipv64_rm _acme-challenge.domain.ipv64.net "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
#Remove the txt record after validation.
dns_ipv64_rm() {
  fulldomain=$1
  txtvalue=$2

  IPv64_Token="${IPv64_Token:-$(_readaccountconf_mutable IPv64_Token)}"
  if [ -z "$IPv64_Token" ]; then
    _err "You must export variable: IPv64_Token"
    _err "The API Key for your IPv64 account is necessary."
    _err "You can look it up in your IPv64 account."
    return 1
  fi

  if ! _get_root "$fulldomain"; then
    _err "invalid domain" "$fulldomain"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  # convert to lower case
  _domain="$(echo "$_domain" | _lower_case)"
  _sub_domain="$(echo "$_sub_domain" | _lower_case)"
  # Now delete the TXT record
  _info "Trying to delete TXT record"
  if _ipv64_rest "DELETE" "del_record=$_domain&praefix=$_sub_domain&type=TXT&content=$txtvalue"; then
    _info "TXT record has been successfully deleted."
    return 0
  else
    _err "Errors happened during deleting the TXT record, response=$_response"
    return 1
  fi

}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
_get_root() {
  domain="$1"
  i=1
  p=1

  _ipv64_get "get_domains"
  domain_data=$_response

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    #if _contains "$domain_data" "\""$h"\"\:"; then
    if _contains "$domain_data" "\"""$h""\"\:"; then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-"$p")
      _domain="$h"
      return 0
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

#send get request to api
# $1 has to set the api-function
_ipv64_get() {
  url="$IPv64_API?$1"
  export _H1="Authorization: Bearer $IPv64_Token"

  _response=$(_get "$url")
  _response="$(echo "$_response" | _normalizeJson)"

  if _contains "$_response" "429 Too Many Requests"; then
    _info "API throttled, sleeping to reset the limit"
    _sleep 10
    _response=$(_get "$url")
    _response="$(echo "$_response" | _normalizeJson)"
  fi
}

_ipv64_rest() {
  url="$IPv64_API"
  export _H1="Authorization: Bearer $IPv64_Token"
  export _H2="Content-Type: application/x-www-form-urlencoded"
  _response=$(_post "$2" "$url" "" "$1")

  if _contains "$_response" "429 Too Many Requests"; then
    _info "API throttled, sleeping to reset the limit"
    _sleep 10
    _response=$(_post "$2" "$url" "" "$1")
  fi

  if ! _contains "$_response" "\"info\":\"success\""; then
    return 1
  fi
  _debug2 response "$_response"
  return 0
}
