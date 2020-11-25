#!/usr/bin/env sh

# Joker.com API for acme.sh
#
# This script adds the necessary TXT record to a domain in Joker.com.
#
# You must activate Dynamic DNS in Joker.com DNS configuration first.
# Username and password below refer to Dynamic DNS authentication,
# not your Joker.com login credentials.
# See: https://joker.com/faq/content/11/427/en/what-is-dynamic-dns-dyndns.html
#
# NOTE: This script does not support wildcard certificates, because
# Joker.com API does not support adding two TXT records with the same
# subdomain. Adding the second record will overwrite the first one.
# See: https://joker.com/faq/content/6/496/en/let_s-encrypt-support.html
#   "... this request will replace all TXT records for the specified
#    label by the provided content"
#
# Author: aattww (https://github.com/aattww/)
#
# Report bugs to https://github.com/acmesh-official/acme.sh/issues/2840
#
# JOKER_USERNAME="xxxx"
# JOKER_PASSWORD="xxxx"

JOKER_API="https://svc.joker.com/nic/replace"

########  Public functions #####################

#Usage: dns_joker_add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_joker_add() {
  fulldomain=$1
  txtvalue=$2

  JOKER_USERNAME="${JOKER_USERNAME:-$(_readaccountconf_mutable JOKER_USERNAME)}"
  JOKER_PASSWORD="${JOKER_PASSWORD:-$(_readaccountconf_mutable JOKER_PASSWORD)}"

  if [ -z "$JOKER_USERNAME" ] || [ -z "$JOKER_PASSWORD" ]; then
    _err "No Joker.com username and password specified."
    return 1
  fi

  _saveaccountconf_mutable JOKER_USERNAME "$JOKER_USERNAME"
  _saveaccountconf_mutable JOKER_PASSWORD "$JOKER_PASSWORD"

  if ! _get_root "$fulldomain"; then
    _err "Invalid domain"
    return 1
  fi

  _info "Adding TXT record"
  if _joker_rest "username=$JOKER_USERNAME&password=$JOKER_PASSWORD&zone=$_domain&label=$_sub_domain&type=TXT&value=$txtvalue"; then
    if _startswith "$response" "OK"; then
      _info "Added, OK"
      return 0
    fi
  fi
  _err "Error adding TXT record."
  return 1
}

#fulldomain txtvalue
dns_joker_rm() {
  fulldomain=$1
  txtvalue=$2

  JOKER_USERNAME="${JOKER_USERNAME:-$(_readaccountconf_mutable JOKER_USERNAME)}"
  JOKER_PASSWORD="${JOKER_PASSWORD:-$(_readaccountconf_mutable JOKER_PASSWORD)}"

  if ! _get_root "$fulldomain"; then
    _err "Invalid domain"
    return 1
  fi

  _info "Removing TXT record"
  # TXT record is removed by setting its value to empty.
  if _joker_rest "username=$JOKER_USERNAME&password=$JOKER_PASSWORD&zone=$_domain&label=$_sub_domain&type=TXT&value="; then
    if _startswith "$response" "OK"; then
      _info "Removed, OK"
      return 0
    fi
  fi
  _err "Error removing TXT record."
  return 1
}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
_get_root() {
  fulldomain=$1
  i=1
  while true; do
    h=$(printf "%s" "$fulldomain" | cut -d . -f $i-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      return 1
    fi

    # Try to remove a test record. With correct root domain, username and password this will return "OK: ..." regardless
    # of record in question existing or not.
    if _joker_rest "username=$JOKER_USERNAME&password=$JOKER_PASSWORD&zone=$h&label=jokerTXTUpdateTest&type=TXT&value="; then
      if _startswith "$response" "OK"; then
        _sub_domain="$(echo "$fulldomain" | sed "s/\\.$h\$//")"
        _domain=$h
        return 0
      fi
    fi

    i=$(_math "$i" + 1)
  done

  _debug "Root domain not found"
  return 1
}

_joker_rest() {
  data="$1"
  _debug data "$data"

  if ! response="$(_post "$data" "$JOKER_API" "" "POST")"; then
    _err "Error POSTing"
    return 1
  fi
  _debug response "$response"
  return 0
}
