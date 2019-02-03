#!/bin/bash

# MyDevil.net API (2019-02-03)
#
# MyDevil.net already supports automatic Let's Encrypt certificates,
# except for wildcard domains.
#
# This script depends on `devil dns` that MyDevil.net provides,
# which means that it works only on server side.
#
# Author: Marcin Konicki <https://ahwayakchih.neoni.net>
#
########  Public functions #####################

#Usage: dns_mydevil_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_mydevil_add() {
  local fulldomain=$1
  local txtvalue=$2
  local domain=""

  _info "Using mydevil"

  domain=$(mydevil_get_domain "$fulldomain")
  if ! mydevil_check_record "$fulldomain"; then
    _err "Invalid record name: does not start with '_acme-challenge'."
    return 1
  fi

  if [ -z  "$domain" ]; then
    _err "Invalid domain name: could not find root domain of $fulldomain."
    return 1
  fi

  _info "Adding $fulldomain record for domain $domain"
  if devil dns add "$domain" "$fulldomain" TXT "$txtvalue"; then
    _info "Successfully added TXT record, ready for validation."
    return 0
  else
    _err "Unable to add DNS record."
    return 1
  fi
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_mydevil_rm() {
  local fulldomain=$1
  local txtvalue=$2
  local domain=""

  _info "Using mydevil"

  domain=$(mydevil_get_domain "$fulldomain")
  if ! mydevil_check_record "$fulldomain"; then
    _err "Invalid record name: does not start with '_acme-challenge'."
    return 1
  fi

  if [ -z  "$domain" ]; then
    _err "Invalid domain name: could not find root domain of $fulldomain."
    return 1
  fi

  for id in $(devil dns list "$domain" | grep "$fulldomain" | awk '{print $1}'); do
    _info "Removing record $id from domain $domain"
    devil dns del "$domain" "$id" || _err "Could not remove DNS record."
  done
}

####################  Private functions below ##################################

# Usage: mydevil_check_record "_acme-challenge.www.domain.com" || _err "Invalid record name"
mydevil_check_record() {
  local record=$1

  case "$record" in
    "_acme-challenge."*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# Usage: domain=$(mydevil_get_domain "_acme-challenge.www.domain.com" || _err "Invalid domain name")
#        echo $domain
mydevil_get_domain() {
  local fulldomain=$1
  local domain=""

  for domain in $(devil dns list | grep . | awk '{if(NR>1)print $1}'); do
    if _endswith "$fulldomain" "$domain"; then
      printf -- "%s" "$domain"
      return 0
    fi
  done

  return 1
}
