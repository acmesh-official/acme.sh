#!/usr/bin/env sh
# -*- mode: sh; tab-width: 2; indent-tabs-mode: s; coding: utf-8 -*-
# vim: et ts=2 sw=2
#
# DirectAdmin 1.41.0 API
# The DirectAdmin interface has it's own Let's encrypt functionality, but this
# script can be used to generate certificates for names which are not hosted on
# DirectAdmin
#
# User must provide login data and URL to DirectAdmin incl. port.
# You can create login key, by using the Login Keys function
# ( https://da.example.com:8443/CMD_LOGIN_KEYS ), which only has access to
# - CMD_API_DNS_CONTROL
# - CMD_API_SHOW_DOMAINS
#
# See also https://www.directadmin.com/api.php and
# https://www.directadmin.com/features.php?id=1298
#
# Report bugs to https://github.com/TigerP/acme.sh/issues
#
# Values to export:
# export DA_Api="https://remoteUser:remotePassword@da.example.com:8443"
# export DA_Api_Insecure=1
#
# Set DA_Api_Insecure to 1 for insecure and 0 for secure -> difference is
# whether ssl cert is checked for validity (0) or whether it is just accepted
# (1)
#
########  Public functions #####################

# Usage: dns_myapi_add  _acme-challenge.www.example.com  "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
# Used to add txt record
dns_da_add() {
  fulldomain="${1}"
  txtvalue="${2}"
  _debug "Calling: dns_da_add() '${fulldomain}' '${txtvalue}'"
  _DA_credentials && _DA_getDomainInfo && _DA_addTxt
}

# Usage: dns_da_rm  _acme-challenge.www.example.com  "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
# Used to remove the txt record after validation
dns_da_rm() {
  fulldomain="${1}"
  txtvalue="${2}"
  _debug "Calling: dns_da_rm() '${fulldomain}' '${txtvalue}'"
  _DA_credentials && _DA_getDomainInfo && _DA_rmTxt
}

####################  Private functions below ##################################
# Usage: _DA_credentials
# It will check if the needed settings are available
_DA_credentials() {
  DA_Api="${DA_Api:-$(_readaccountconf_mutable DA_Api)}"
  DA_Api_Insecure="${DA_Api_Insecure:-$(_readaccountconf_mutable DA_Api_Insecure)}"
  if [ -z "${DA_Api}" ] || [ -z "${DA_Api_Insecure}" ]; then
    DA_Api=""
    DA_Api_Insecure=""
    _err "You haven't specified the DirectAdmin Login data, URL and whether you want check the DirectAdmin SSL cert. Please try again."
    return 1
  else
    _saveaccountconf_mutable DA_Api "${DA_Api}"
    _saveaccountconf_mutable DA_Api_Insecure "${DA_Api_Insecure}"
    # Set whether curl should use secure or insecure mode
    export HTTPS_INSECURE="${DA_Api_Insecure}"
  fi
}

# Usage: _get_root _acme-challenge.www.example.com
# Split the full domain to a domain and subdomain
#returns
# _sub_domain=_acme-challenge.www
# _domain=example.com
_get_root() {
  domain=$1
  i=2
  p=1
  # Get a list of all the domains
  # response will contain "list[]=example.com&list[]=example.org"
  _da_api CMD_API_SHOW_DOMAINS "" "${domain}"
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      # not valid
      _debug "The given domain $h is not valid"
      return 1
    fi
    if _contains "$response" "$h" >/dev/null; then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
      _domain=$h
      return 0
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  _debug "Stop on 100"
  return 1
}

# Usage: _da_api CMD_API_* data example.com
# Use the DirectAdmin API and check the result
# returns
#  response="error=0&text=Result text&details="
_da_api() {
  cmd=$1
  data=$2
  domain=$3
  _debug "$domain; $data"
  response="$(_post "$data" "$DA_Api/$cmd" "" "POST")"

  if [ "$?" != "0" ]; then
    _err "error $cmd"
    return 1
  fi
  _debug response "$response"

  case "${cmd}" in
  CMD_API_DNS_CONTROL)
    # Parse the result in general
    # error=0&text=Records Deleted&details=
    # error=1&text=Cannot View Dns Record&details=No domain provided
    err_field="$(_getfield "$response" 1 '&')"
    txt_field="$(_getfield "$response" 2 '&')"
    details_field="$(_getfield "$response" 3 '&')"
    error="$(_getfield "$err_field" 2 '=')"
    text="$(_getfield "$txt_field" 2 '=')"
    details="$(_getfield "$details_field" 2 '=')"
    _debug "error: ${error}, text: ${text}, details: ${details}"
    if [ "$error" != "0" ]; then
      _err "error $response"
      return 1
    fi
    ;;
  CMD_API_SHOW_DOMAINS) ;;
  esac
  return 0
}

# Usage: _DA_getDomainInfo
# Get the root zone if possible
_DA_getDomainInfo() {
  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  else
    _debug "The root domain: $_domain"
    _debug "The sub domain: $_sub_domain"
  fi
  return 0
}

# Usage: _DA_addTxt
# Use the API to add a record
_DA_addTxt() {
  curData="domain=${_domain}&action=add&type=TXT&name=${_sub_domain}&value=\"${txtvalue}\""
  _debug "Calling _DA_addTxt: '${curData}' '${DA_Api}/CMD_API_DNS_CONTROL'"
  _da_api CMD_API_DNS_CONTROL "${curData}" "${_domain}"
  _debug "Result of _DA_addTxt: '$response'"
  if _contains "${response}" 'error=0'; then
    _debug "Add TXT succeeded"
    return 0
  fi
  _debug "Add TXT failed"
  return 1
}

# Usage: _DA_rmTxt
# Use the API to remove a record
_DA_rmTxt() {
  curData="domain=${_domain}&action=select&txtrecs0=name=${_sub_domain}&amp;value=\"${txtvalue}\""
  _debug "Calling _DA_rmTxt: '${curData}' '${DA_Api}/CMD_API_DNS_CONTROL'"
  if _da_api CMD_API_DNS_CONTROL "${curData}" "${_domain}"; then
    _debug "Result of _DA_rmTxt: '$response'"
  else
    _err "Result of _DA_rmTxt: '$response'"
  fi
  if _contains "${response}" 'error=0'; then
    _debug "RM TXT succeeded"
    return 0
  fi
  _debug "RM TXT failed"
  return 1
}
