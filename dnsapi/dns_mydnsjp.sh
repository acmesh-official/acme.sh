#!/usr/bin/env sh

#Here is a api script for MyDNS.JP.
#This file name is "dns_mydnsjp.sh"
#So, here must be a method   dns_mydnsjp_add()
#Which will be called by acme.sh to add the txt record to your api system.
#returns 0 means success, otherwise error.
#
#Author: epgdatacapbon
#Report Bugs here: https://github.com/epgdatacapbon/acme.sh
#
########  Public functions #####################

# Export MyDNS.JP MasterID and Password in following variables...
#  MYDNSJP_MasterID=MasterID
#  MYDNSJP_Password=Password

MYDNSJP_API="https://www.mydns.jp"

#Usage: dns_mydnsjp_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_mydnsjp_add() {
  fulldomain=$1
  txtvalue=$2

  _info "Using mydnsjp"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  # Load the credentials from the account conf file
  MYDNSJP_MasterID="${MYDNSJP_MasterID:-$(_readaccountconf_mutable MYDNSJP_MasterID)}"
  MYDNSJP_Password="${MYDNSJP_Password:-$(_readaccountconf_mutable MYDNSJP_Password)}"
  if [ -z "$MYDNSJP_MasterID" ] || [ -z "$MYDNSJP_Password" ]; then
    MYDNSJP_MasterID=""
    MYDNSJP_Password=""
    _err "You don't specify mydnsjp api MasterID and Password yet."
    _err "Please export as MYDNSJP_MasterID / MYDNSJP_Password and try again."
    return 1
  fi

  # Save the credentials to the account conf file
  _saveaccountconf_mutable MYDNSJP_MasterID "$MYDNSJP_MasterID"
  _saveaccountconf_mutable MYDNSJP_Password "$MYDNSJP_Password"

  _debug "First detect the root zone."
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  if _mydnsjp_api "REGIST" "$_domain" "$txtvalue"; then
    if printf -- "%s" "$response" | grep "OK." >/dev/null; then
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
dns_mydnsjp_rm() {
  fulldomain=$1
  txtvalue=$2

  _info "Removing TXT record"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  # Load the credentials from the account conf file
  MYDNSJP_MasterID="${MYDNSJP_MasterID:-$(_readaccountconf_mutable MYDNSJP_MasterID)}"
  MYDNSJP_Password="${MYDNSJP_Password:-$(_readaccountconf_mutable MYDNSJP_Password)}"
  if [ -z "$MYDNSJP_MasterID" ] || [ -z "$MYDNSJP_Password" ]; then
    MYDNSJP_MasterID=""
    MYDNSJP_Password=""
    _err "You don't specify mydnsjp api MasterID and Password yet."
    _err "Please export as MYDNSJP_MasterID / MYDNSJP_Password and try again."
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  if _mydnsjp_api "DELETE" "$_domain" "$txtvalue"; then
    if printf -- "%s" "$response" | grep "OK." >/dev/null; then
      _info "Deleted, OK"
      return 0
    else
      _err "Delete txt record error."
      return 1
    fi
  fi
  _err "Delete txt record error."

  return 1
}

####################  Private functions below ##################################
# _acme-challenge.www.domain.com
# returns
#  _sub_domain=_acme-challenge.www
#  _domain=domain.com
_get_root() {
  fulldomain=$1
  i=2
  p=1

  # Get the root domain
  _mydnsjp_retrieve_domain
  if [ "$?" != "0" ]; then
    # not valid
    return 1
  fi

  while true; do
    _domain=$(printf "%s" "$fulldomain" | cut -d . -f $i-100)

    if [ -z "$_domain" ]; then
      # not valid
      return 1
    fi

    if [ "$_domain" = "$_root_domain" ]; then
      _sub_domain=$(printf "%s" "$fulldomain" | cut -d . -f 1-$p)
      return 0
    fi

    p=$i
    i=$(_math "$i" + 1)
  done

  return 1
}

# Retrieve the root domain
# returns 0 success
_mydnsjp_retrieve_domain() {
  _debug "Login to MyDNS.JP"

  response="$(_post "masterid=$MYDNSJP_MasterID&masterpwd=$MYDNSJP_Password" "$MYDNSJP_API/?MENU=100")"
  cookie="$(grep -i '^set-cookie:' "$HTTP_HEADER" | _head_n 1 | cut -d " " -f 2)"

  # If cookies is not empty then logon successful
  if [ -z "$cookie" ]; then
    _err "Fail to get a cookie."
    return 1
  fi

  _debug "Retrieve DOMAIN INFO page"

  export _H1="Cookie:${cookie}"

  response="$(_get "$MYDNSJP_API/?MENU=300")"

  if [ "$?" != "0" ]; then
    _err "Fail to retrieve DOMAIN INFO."
    return 1
  fi

  _root_domain=$(echo "$response" | grep "DNSINFO\[domainname\]" | sed 's/^.*value="\([^"]*\)".*/\1/')

  # Logout
  response="$(_get "$MYDNSJP_API/?MENU=090")"

  _debug _root_domain "$_root_domain"

  if [ -z "$_root_domain" ]; then
    _err "Fail to get the root domain."
    return 1
  fi

  return 0
}

_mydnsjp_api() {
  cmd=$1
  domain=$2
  txtvalue=$3

  # Base64 encode the credentials
  credentials=$(printf "%s:%s" "$MYDNSJP_MasterID" "$MYDNSJP_Password" | _base64)

  # Construct the HTTP Authorization header
  export _H1="Content-Type: application/x-www-form-urlencoded"
  export _H2="Authorization: Basic ${credentials}"

  response="$(_post "CERTBOT_DOMAIN=$domain&CERTBOT_VALIDATION=$txtvalue&EDIT_CMD=$cmd" "$MYDNSJP_API/directedit.html")"

  if [ "$?" != "0" ]; then
    _err "error $domain"
    return 1
  fi

  _debug2 response "$response"

  return 0
}
