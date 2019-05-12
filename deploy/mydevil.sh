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

# Usage: mydevil_deploy domain keyfile certfile cafile fullchain
mydevil_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"
  ip=""

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"

  if ! _exists "devil"; then
    _err "Could not find 'devil' command."
    return 1
  fi

  ip=$(mydevil_get_ip "$_cdomain")
  if [ -z "$ip" ]; then
    _err "Could not find IP for domain $_cdomain."
    return 1
  fi

  # Delete old certificate first
  _info "Removing old certificate for $_cdomain at $ip"
  devil ssl www del "$ip" "$_cdomain"

  # Add new certificate
  _info "Adding new certificate for $_cdomain at $ip"
  devil ssl www add "$ip" "$_cfullchain" "$_ckey" "$_cdomain" || return 1

  return 0
}

####################  Private functions below ##################################

# Usage: ip=$(mydevil_get_ip domain.com)
#        echo $ip
mydevil_get_ip() {
  devil dns list "$1" | cut -w -s -f 3,7 | grep "^A$(printf '\t')" | cut -w -s -f 2 || return 1
  return 0
}
