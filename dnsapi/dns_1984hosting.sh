#!/usr/bin/env sh
#This file name is "dns_1984hosting.sh"
#So, here must be a method dns_1984hosting_add()
#Which will be called by acme.sh to add the txt record to your api system.
#returns 0 means success, otherwise error.

#Author: Adrian Fedoreanu
#Report Bugs here: https://github.com/acmesh-official/acme.sh
# or here... https://github.com/acmesh-official/acme.sh/issues/2851
#
########  Public functions #####################

# Export 1984HOSTING username and password in following variables
#
#  One984HOSTING_Username=username
#  One984HOSTING_Password=password
#
# sessionid cookie is saved in ~/.acme.sh/account.conf
# username/password need to be set only when changed.

#Usage: dns_1984hosting_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_1984hosting_add() {
  fulldomain=$1
  txtvalue=$2

  _info "Add TXT record using 1984Hosting"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  if ! _1984hosting_login; then
    _err "1984Hosting login failed for user $One984HOSTING_Username. Check $HTTP_HEADER file"
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain" "$fulldomain"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Add TXT record $fulldomain with value '$txtvalue'"
  value="$(printf '%s' "$txtvalue" | _url_encode)"
  url="https://management.1984hosting.com/domains/entry/"

  postdata="entry=new"
  postdata="$postdata&type=TXT"
  postdata="$postdata&ttl=900"
  postdata="$postdata&zone=$_domain"
  postdata="$postdata&host=$_sub_domain"
  postdata="$postdata&rdata=%22$value%22"
  _debug2 postdata "$postdata"

  _authpost "$postdata" "$url"
  response="$(echo "$_response" | _normalizeJson)"
  _debug2 response "$response"

  if _contains "$response" '"haserrors": true'; then
    _err "1984Hosting failed to add TXT record for $_sub_domain bad RC from _post"
    return 1
  elif _contains "$response" "html>"; then
    _err "1984Hosting failed to add TXT record for $_sub_domain. Check $HTTP_HEADER file"
    return 1
  elif _contains "$response" '"auth": false'; then
    _err "1984Hosting failed to add TXT record for $_sub_domain. Invalid or expired cookie"
    return 1
  fi

  _info "Added acme challenge TXT record for $fulldomain at 1984Hosting"
  return 0
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_1984hosting_rm() {
  fulldomain=$1
  txtvalue=$2

  _info "Delete TXT record using 1984Hosting"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  if ! _1984hosting_login; then
    _err "1984Hosting login failed for user $One984HOSTING_Username. Check $HTTP_HEADER file"
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain" "$fulldomain"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"
  _debug "Delete $fulldomain TXT record"

  url="https://management.1984hosting.com/domains"
  if ! _get_zone_id "$url" "$_domain"; then
    _err "invalid zone" "$_domain"
    return 1
  fi

  _htmlget "$url/$_zone_id" "$txtvalue"
  _debug2 _response "$_response"
  entry_id="$(echo "$_response" | _egrep_o 'entry_[0-9]+' | sed 's/entry_//')"
  _debug2 entry_id "$entry_id"
  if [ -z "$entry_id" ]; then
    _err "Error getting TXT entry_id for $1"
    return 1
  fi

  _authpost "entry=$entry_id" "$url/delentry/"
  response="$(echo "$_response" | _normalizeJson)"
  _debug2 response "$response"

  if ! _contains "$response" '"ok": true'; then
    _err "1984Hosting failed to delete TXT record for $entry_id bad RC from _post"
    return 1
  fi

  _info "Deleted acme challenge TXT record for $fulldomain at 1984Hosting"
  return 0
}

####################  Private functions below ##################################

# usage: _1984hosting_login username password
# returns 0 success
_1984hosting_login() {
  if ! _check_credentials; then return 1; fi

  if _check_cookies; then
    _debug "Already logged in"
    return 0
  fi

  _debug "Login to 1984Hosting as user $One984HOSTING_Username"
  username=$(printf '%s' "$One984HOSTING_Username" | _url_encode)
  password=$(printf '%s' "$One984HOSTING_Password" | _url_encode)
  url="https://management.1984hosting.com/accounts/checkuserauth/"

  response="$(_post "username=$username&password=$password&otpkey=" $url)"
  response="$(echo "$response" | _normalizeJson)"
  _debug2 response "$response"

  if _contains "$response" '"loggedin": true'; then
    One984HOSTING_SESSIONID_COOKIE="$(grep -i '^set-cookie:' "$HTTP_HEADER" | _egrep_o 'sessionid=[^;]*;' | tr -d ';')"
    One984HOSTING_CSRFTOKEN_COOKIE="$(grep -i '^set-cookie:' "$HTTP_HEADER" | _egrep_o 'csrftoken=[^;]*;' | tr -d ';')"
    export One984HOSTING_SESSIONID_COOKIE
    export One984HOSTING_CSRFTOKEN_COOKIE
    _saveaccountconf_mutable One984HOSTING_SESSIONID_COOKIE "$One984HOSTING_SESSIONID_COOKIE"
    _saveaccountconf_mutable One984HOSTING_CSRFTOKEN_COOKIE "$One984HOSTING_CSRFTOKEN_COOKIE"
    return 0
  fi
  return 1
}

_check_credentials() {
  if [ -z "$One984HOSTING_Username" ] || [ -z "$One984HOSTING_Password" ]; then
    One984HOSTING_Username=""
    One984HOSTING_Password=""
    _err "You haven't specified 1984Hosting username or password yet."
    _err "Please export as One984HOSTING_Username / One984HOSTING_Password and try again."
    return 1
  fi
  return 0
}

_check_cookies() {
  One984HOSTING_SESSIONID_COOKIE="${One984HOSTING_SESSIONID_COOKIE:-$(_readaccountconf_mutable One984HOSTING_SESSIONID_COOKIE)}"
  One984HOSTING_CSRFTOKEN_COOKIE="${One984HOSTING_CSRFTOKEN_COOKIE:-$(_readaccountconf_mutable One984HOSTING_CSRFTOKEN_COOKIE)}"
  if [ -z "$One984HOSTING_SESSIONID_COOKIE" ] || [ -z "$One984HOSTING_CSRFTOKEN_COOKIE" ]; then
    _debug "No cached cookie(s) found"
    return 1
  fi

  _authget "https://management.1984hosting.com/accounts/loginstatus/"
  if _contains "$response" '"ok": true'; then
    _debug "Cached cookies still valid"
    return 0
  fi
  _debug "Cached cookies no longer valid"
  One984HOSTING_SESSIONID_COOKIE=""
  One984HOSTING_CSRFTOKEN_COOKIE=""
  _saveaccountconf_mutable One984HOSTING_SESSIONID_COOKIE "$One984HOSTING_SESSIONID_COOKIE"
  _saveaccountconf_mutable One984HOSTING_CSRFTOKEN_COOKIE "$One984HOSTING_CSRFTOKEN_COOKIE"
  return 1
}

#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
_get_root() {
  domain="$1"
  i=1
  p=1
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)

    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    _authget "https://management.1984hosting.com/domains/soacheck/?zone=$h&nameserver=ns0.1984.is."
    if _contains "$_response" "serial" && ! _contains "$_response" "null"; then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
      _domain="$h"
      return 0
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

#usage: _get_zone_id url domain.com
#returns zone id for domain.com
_get_zone_id() {
  url=$1
  domain=$2
  _htmlget "$url" "$domain"
  _debug2 _response "$_response"
  _zone_id="$(echo "$_response" | _egrep_o 'zone\/[0-9]+' | _head_n 1)"
  _debug2 _zone_id "$_zone_id"
  if [ -z "$_zone_id" ]; then
    _err "Error getting _zone_id for $2"
    return 1
  fi
  return 0
}

# add extra headers to request
_authget() {
  export _H1="Cookie: $One984HOSTING_CSRFTOKEN_COOKIE;$One984HOSTING_SESSIONID_COOKIE"
  _response=$(_get "$1" | _normalizeJson)
  _debug2 _response "$_response"
}

# truncate huge HTML response
# echo: Argument list too long
_htmlget() {
  export _H1="Cookie: $One984HOSTING_CSRFTOKEN_COOKIE;$One984HOSTING_SESSIONID_COOKIE"
  _response=$(_get "$1" | grep "$2")
  if _contains "$_response" "@$2"; then
    _response=$(echo "$_response" | grep -v "[@]" | _head_n 1)
  fi
}

# add extra headers to request
_authpost() {
  url="https://management.1984hosting.com/domains"
  _get_zone_id "$url" "$_domain"
  csrf_header="$(echo "$One984HOSTING_CSRFTOKEN_COOKIE" | _egrep_o "=[^=][0-9a-zA-Z]*" | tr -d "=")"
  export _H1="Cookie: $One984HOSTING_CSRFTOKEN_COOKIE;$One984HOSTING_SESSIONID_COOKIE"
  export _H2="Referer: https://management.1984hosting.com/domains/$_zone_id"
  export _H3="X-CSRFToken: $csrf_header"
  _response=$(_post "$1" "$2")
}
