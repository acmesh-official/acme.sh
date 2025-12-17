#!/usr/bin/env sh
#!!!!!!!!!!!!!!!!!!!!!!! Important !!!!!!!!!!!!!!!!!!!!!!
#! Make sure the verson of ISPMan supports TXT records  !
#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

######################## Forward ########################

#This file name is "dns_ispman.sh"
#So, here must be a method dns_ispman_add()
#Which will be called by acme.sh to add the txt record to your api system.
#returns 0 means success, otherwise error.

#Authored by Adrian Fedoreanu (dns_1984hosting.sh)
#Modified by Gary C. New (dns_ispman.sh)
#Report Bugs here: https://github.com/acmesh-official/acme.sh
# or here... https://github.com/acmesh-official/acme.sh/issues/????

#################### Public Functions ####################

# Export ISPMan Username and Password in following variables
#
# export ACME_USE_WGET=1
# export ISPMan_Username=domain
# export ISPMan_Password=passwd
#
# Domain Cookie is saved in $LE_WORKING_DIR/account.conf
# Username/Password need to be set only when changed.

# While ISPMan does not work with acme.sh curl implementation
# Force acme.sh to use wget by exporting the following variable

export ACME_USE_WGET=1

#Usage: dns_ispman_add   _acme-challenge.www.domain.tld   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_ispman_add() {
  fulldomain=$1
  domainname="$(echo ${fulldomain#_acme-challenge.} | sed "s/\-/_HYPHEN_/g" | sed "s/\./_DOT_/g")"
  txtvalue=$2

  _info "Add TXT record using ISPMan"
  _debug fulldomain "$fulldomain"
  _debug domainname "$domainname"
  _debug txtvalue "$txtvalue"

  # fulldomain="_acme-challenge.example-domain.tld"; domain="${domain:-$(echo domain_${fulldomain#_acme-challenge.}_name)}"; echo "$domain"
  ISPMan_Username="${ISPMan_Username:-$(_readaccountconf_mutable ISPMan_${domainname}_Username)}"
  ISPMan_Password="${ISPMan_Password:-$(_readaccountconf_mutable ISPMan_${domainname}_Password)}"

  _debug2 ISPMan_Username "$ISPMan_Username"
  _debug2 "ISPMan_${domainname}_Username" "${ISPMan_Username:-$(_readaccountconf_mutable ISPMan_${domainname}_Username)}"

  if ! _ispman_login; then
    _err "ISPMan login failed for user $ISPMan_Username. Check $HTTP_HEADER file"
    return 1
  fi

  _saveaccountconf_mutable ISPMan_${domainname}_Username "$ISPMan_Username"
  _saveaccountconf_mutable ISPMan_${domainname}_Password "$ISPMan_Password"

  chmod 600 "$LE_WORKING_DIR/account.conf"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain" "$fulldomain"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Add TXT record $fulldomain with value '$txtvalue'"
  host="$(printf '%s' "$fulldomain" | _url_encode)"
  text="$(printf '%s' "$txtvalue" | _url_encode)"
  url="http://192.168.0.49/secure/ispman/control_panel/index.cgi"
  url="$url?mode=addDNSRecord&type=txt&host=$host&text=$text"
  _debug2 url "$url"

  #_authpost "$postdata" "$url"
  _authget "$url"
  response="$(echo "$_response" | _normalizeJson)"
  _debug2 response "$response"

  if _contains "$response" "Unauthorized"; then
    _err "ISPMan failed to add TXT record for $_sub_domain. Invalid or expired cookie"
    return 1
  fi

  _info "Added acme challenge TXT record for $fulldomain at ISPMan"
  return 0
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_ispman_rm() {
  fulldomain=$1
  domainname="$(echo ${fulldomain#_acme-challenge.} | sed "s/\-/_HYPHEN_/g" | sed "s/\./_DOT_/g")"
  txtvalue=$2

  _info "Delete TXT record using ISPMan"
  _debug fulldomain "$fulldomain"
  _debug domainname "$domainname"
  _debug txtvalue "$txtvalue"

  # fulldomain="_acme-challenge.example-domain.tld"; domain="${domain:-$(echo domain_${fulldomain#_acme-challenge.}_name)}"; echo "$domain"
  ISPMan_Username="${ISPMan_Username:-$(_readaccountconf_mutable ISPMan_${domainname}_Username)}"
  ISPMan_Password="${ISPMan_Password:-$(_readaccountconf_mutable ISPMan_${domainname}_Password)}"

  _debug2 ISPMan_Username "$ISPMan_Username"
  _debug2 "ISPMan_${domainname}_Username" "${ISPMan_Username:-$(_readaccountconf_mutable ISPMan_${domainname}_Username)}"

  if ! _ispman_login; then
    _err "ISPMan login failed for user $ISPMan_Username. Check $HTTP_HEADER file"
    return 1
  fi

  _saveaccountconf_mutable ISPMan_${domainname}_Username "$ISPMan_Username"
  _saveaccountconf_mutable ISPMan_${domainname}_Password "$ISPMan_Password"

  chmod 600 "$LE_WORKING_DIR/account.conf"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain" "$fulldomain"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"
  _debug "Delete $fulldomain TXT record"

  host="$(printf '%s' "$fulldomain" | _url_encode)"                             
  text="$(printf '%s' "$txtvalue" | _url_encode)"                               
  url="http://192.168.0.49/secure/ispman/control_panel/index.cgi"               
  url="$url?mode=deleteDNSRecord&type=txt&host=$host&text=$text"
  _debug2 url "$url"

  _authget "$url"
  response="$(echo "$_response" | _normalizeJson)"
  _debug2 response "$response"

  if _contains "$response" "Unauthorized"; then
    _err "ISPMan failed to delete TXT record for $_sub_domain. Invalid or expired cookie"
    return 1
  fi

  _info "Deleted acme challenge TXT record for $fulldomain at ISPMan"
  return 0
}

#################### Private Functions ####################

# usage: _ispman_login username password
# returns 0 success
_ispman_login() {
  if ! _check_credentials; then return 1; fi

  if _check_cookies; then
    _debug "Already logged in"
    return 0
  fi

  _debug "Login to ISPMan as user $ISPMan_Username"
  username=$(printf '%s' "$ISPMan_Username" | _url_encode)
  password=$(printf '%s' "$ISPMan_Password" | _url_encode)
  url="http://192.168.0.49/secure/ispman/control_panel/index.cgi?mode=index"

  # _post(body  url [needbase64] [POST|PUT|DELETE] [ContentType])
  #response="$(_post "domain=$username&pass=$password" $url "" "POST" "application/x-www-form-urlencoded")"
  response="$(_post "domain=$username&pass=$password" $url)"
  response="$(echo "$response" | _normalizeJson)"
  _debug2 response "$response"

  if _contains "$response" "$username"; then
    # Set-Cookie: domain=domain.tld; path=/; expires=1h
    ISPMan_COOKIE="$(grep -i '^set-cookie:' "$HTTP_HEADER" | _egrep_o 'domain=[^;]*;' | tr -d ';')"
    export ISPMan_COOKIE
    _saveaccountconf_mutable ISPMan_${domainname}_COOKIE "$ISPMan_COOKIE"
    return 0
  fi
  return 1
}

_check_credentials() {
  if [ -z "$ISPMan_Username" ] || [ -z "$ISPMan_Password" ]; then
    ISPMan_Username=""
    ISPMan_Password=""
    _err "You haven't specified ISPMan Username or Password yet."
    _err "Please export as ISPMan_Username / ISPMan_Password and try again."
    return 1
  fi
  return 0
}

_check_cookies() {
  ISPMan_COOKIE="${ISPMan_COOKIE:-$(_readaccountconf_mutable ISPMan_${domainname}_COOKIE)}"
  if [ -z "$ISPMan_COOKIE" ]; then
    _debug "No cached cookie(s) found"
    return 1
  fi

  _authget "http://192.168.0.49/secure/ispman/control_panel/index.cgi"
  if _contains "$response" "$username"; then
    _debug "Cached cookies still valid"
    return 0
  fi

  _debug "Cached cookies no longer valid"
  ISPMan_COOKIE=""
  _saveaccountconf_mutable ISPMan_${domainname}_COOKIE "$ISPMan_COOKIE"
  return 1
}

#_acme-challenge.www.domain.tld
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.tld
_get_root() {
  domain="$1"
  i=1
  p=1
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug2 h "$h"

    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    # The ISPMan Customer Control Panel doesn't allow access to the SOA Record
    # The ISPMan_Username is the Domain Root for the Customer Control Panel
    if _startswith "$h" "$ISPMan_Username"; then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
      _domain="$h"
      return 0
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

# add extra headers to request
_authget() {
  export _H1="Cookie: $ISPMan_COOKIE"
  _response=$(_get "$1" | _normalizeJson)
  _debug2 _response "$_response"
}

# truncate huge HTML response
# echo: Argument list too long
_htmlget() {
  export _H1="Cookie: $ISPMan_COOKIE"
  _response=$(_get "$1" | grep "$2")
  if _contains "$_response" "@$2"; then
    _response=$(echo "$_response" | grep -v "[@]" | _head_n 1)
  fi
}

# add extra headers to request
_authpost() {
  export _H1="Cookie: $ISPMan_COOKIE"
  _response=$(_post "$1" $2 | _normalizeJson)
  _debug2 _response "$_response"
}
