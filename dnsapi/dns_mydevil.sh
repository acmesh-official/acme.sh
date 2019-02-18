#!/usr/bin/env sh

# MyDevil.net API (2019-02-03)
#
# MyDevil.net already supports automatic Let's Encrypt certificates,
# except for wildcard domains.
#
# This script depends on `devil` command that MyDevil.net provides,
# which means that it works only on server side.
#
# Author: Marcin Konicki <https://ahwayakchih.neoni.net>
#
########  Public functions #####################

#Usage: dns_mydevil_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_mydevil_add() {
  fulldomain=$1
  txtvalue=$2
  domain=""

  if ! _exists "devil"; then
    _err "Could not find 'devil' command."
    return 1
  fi

  _info "Using mydevil"

  domain=$(mydevil_get_domain "$fulldomain")
  if [ -z "$domain" ]; then
    _err "Invalid domain name: could not find root domain of $fulldomain."
    return 1
  fi

  # No need to check if record name exists, `devil` always adds new record.
  # In worst case scenario, we end up with multiple identical records.

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
  fulldomain=$1
  txtvalue=$2
  domain=""

  if ! _exists "devil"; then
    _err "Could not find 'devil' command."
    return 1
  fi

  _info "Using mydevil"

  domain=$(mydevil_get_domain "$fulldomain")
  if [ -z "$domain" ]; then
    _err "Invalid domain name: could not find root domain of $fulldomain."
    return 1
  fi

  # catch one or more numbers
  num='[0-9][0-9]*'
  # catch one or more whitespace
  w=$(printf '[\t ][\t ]*')
  # catch anything, except newline
  any='.*'
  # filter to make sure we do not delete other records
  validRecords="^${num}${w}${fulldomain}${w}TXT${w}${any}${txtvalue}$"
  for id in $(devil dns list "$domain" | tail -n+2 | grep "${validRecords}" | cut -w -s -f 1); do
    _info "Removing record $id from domain $domain"
    devil dns del "$domain" "$id" || _err "Could not remove DNS record."
  done
}

####################  Private functions below ##################################

# Usage: domain=$(mydevil_get_domain "_acme-challenge.www.domain.com" || _err "Invalid domain name")
#        echo $domain
mydevil_get_domain() {
  fulldomain=$1
  domain=""

  for domain in $(devil dns list | cut -w -s -f 1 | tail -n+2); do
    if _endswith "$fulldomain" "$domain"; then
      printf -- "%s" "$domain"
      return 0
    fi
  done

  return 1
}
