#!/usr/bin/env sh

# united-domains Reselling (https://www.ud-reselling.com/) DNS API
# Author: Andreas Scherer (https://github.com/andischerer)
# Created: 2021-02-01
#
# Set the environment variables as below:
#
#    export UDR_USER="your_username_goes_here"
#    export UDR_PASS="some_password_goes_here"
#

UDR_API="https://api.domainreselling.de/api/call.cgi"
UDR_TTL="30"

########  Public functions #####################

#Usage: add _acme-challenge.www.domain.com "some_long_string_of_characters_go_here_from_lets_encrypt"
dns_udr_add() {
  fulldomain=$1
  txtvalue=$2

  UDR_USER="${UDR_USER:-$(_readaccountconf_mutable UDR_USER)}"
  UDR_PASS="${UDR_PASS:-$(_readaccountconf_mutable UDR_PASS)}"
  if [ -z "$UDR_USER" ] || [ -z "$UDR_PASS" ]; then
    UDR_USER=""
    UDR_PASS=""
    _err "You didn't specify an UD-Reselling username and password yet"
    return 1
  fi
  # save the username and password to the account conf file.
  _saveaccountconf_mutable UDR_USER "$UDR_USER"
  _saveaccountconf_mutable UDR_PASS "$UDR_PASS"
  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _dnszone "${_dnszone}"

  _debug "Getting txt records"
  if ! _udr_rest "QueryDNSZoneRRList" "dnszone=${_dnszone}"; then
    return 1
  fi

  rr="${fulldomain}. ${UDR_TTL} IN TXT ${txtvalue}"
  _debug resource_record "${rr}"
  if _contains "$response" "$rr" >/dev/null; then
    _err "Error, it would appear that this record already exists. Please review existing TXT records for this domain."
    return 1
  fi

  _info "Adding record"
  if ! _udr_rest "UpdateDNSZone" "dnszone=${_dnszone}&addrr0=${rr}"; then
    _err "Adding the record did not succeed, please verify/check."
    return 1
  fi

  _info "Added, OK"
  return 0
}

dns_udr_rm() {
  fulldomain=$1
  txtvalue=$2

  UDR_USER="${UDR_USER:-$(_readaccountconf_mutable UDR_USER)}"
  UDR_PASS="${UDR_PASS:-$(_readaccountconf_mutable UDR_PASS)}"
  if [ -z "$UDR_USER" ] || [ -z "$UDR_PASS" ]; then
    UDR_USER=""
    UDR_PASS=""
    _err "You didn't specify an UD-Reselling username and password yet"
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _dnszone "${_dnszone}"

  _debug "Getting txt records"
  if ! _udr_rest "QueryDNSZoneRRList" "dnszone=${_dnszone}"; then
    return 1
  fi

  rr="${fulldomain}. ${UDR_TTL} IN TXT ${txtvalue}"
  _debug resource_record "${rr}"
  if _contains "$response" "$rr" >/dev/null; then
    if ! _udr_rest "UpdateDNSZone" "dnszone=${_dnszone}&delrr0=${rr}"; then
      _err "Deleting the record did not succeed, please verify/check."
      return 1
    fi
    _info "Removed, OK"
    return 0
  else
    _info "Text record is not present, will not delete anything."
    return 0
  fi
}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
_get_root() {
  domain=$1
  i=1

  if ! _udr_rest "QueryDNSZoneList" ""; then
    return 1
  fi

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug h "$h"

    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    if _contains "${response}" "${h}." >/dev/null; then
      _dnszone=$(echo "$response" | _egrep_o "${h}")
      if [ "$_dnszone" ]; then
        return 0
      fi
      return 1
    fi
    i=$(_math "$i" + 1)
  done
  return 1
}

_udr_rest() {
  if [ -n "$2" ]; then
    data="command=$1&$2"
  else
    data="command=$1"
  fi

  _debug data "${data}"
  response="$(_post "${data}" "${UDR_API}?s_login=${UDR_USER}&s_pw=${UDR_PASS}" "" "POST")"

  _code=$(echo "$response" | _egrep_o "code = ([0-9]+)" | _head_n 1 | cut -d = -f 2 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  _description=$(echo "$response" | _egrep_o "description = .*" | _head_n 1 | cut -d = -f 2 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

  _debug response_code "$_code"
  _debug response_description "$_description"

  if [ ! "$_code" = "200" ]; then
    _err "DNS-API-Error: $_description"
    return 1
  fi

  return 0
}
