#!/usr/bin/env sh

########################################################################
# Hurricane Electric hook script for acme.sh (dynamic TXT API)
#
# These are the pros and cons of dns_he_dyntxt, compared to dns_he:
# Pros:
# - No need to store a dns.he.net account password on your server
# - Uses a very simple write-only API
# Cons:
# - You must manually create placeholder _acme-challenge TXT records,
#   and generate/copy the same DDNS key across all records.
# - This script WILL FAIL to issue both a domain and its wildcard, because
#   '-d example.com -d *.example.com' requires multiple TXT records.
#   Switch to 'dns_he' if you need this feature.
#
# Environment variable:
#   HE_DynTXT_Key - DDNS key for all _acme-challenge TXT records
########################################################################

# Cheat sheet for passing the DNS.yml API test:
# - Set TEST_DNS_NO_WILDCARD=1
# - Create placeholder TXT records for the following domain names:
#   - _acme-challenge.$TestingDomain
#   - acmetestXyzRandomName.$TestingDomain

HE_DynTXT_Api="https://dyn.dns.he.net/nic/update"

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_he_dyntxt_add() {
  fulldomain=$1
  txtvalue=$2

  HE_DynTXT_Key="${HE_DynTXT_Key:-$(_readaccountconf_mutable HE_DynTXT_Key)}"

  if [ -z "$HE_DynTXT_Key" ]; then
    HE_DynTXT_Key=""
    _err "Missing HE_DynTXT_Key. See dnsapi/dns_he_dyntxt.sh for instructions."
    return 1
  fi

  #save the DDNS key to the account conf file.
  _saveaccountconf_mutable HE_DynTXT_Key "$HE_DynTXT_Key"

  _info "Updating record $fulldomain"
  _he_dyntxt_post "$fulldomain" "$txtvalue"
  return "$?"
}

dns_he_dyntxt_rm() {
  fulldomain=$1
  txtvalue='""' # The record is just cleared, not removed.

  HE_DynTXT_Key="${HE_DynTXT_Key:-$(_readaccountconf_mutable HE_DynTXT_Key)}"

  _info "Clearing record $fulldomain"
  _he_dyntxt_post "$fulldomain" "$txtvalue"
  return "$?"
}

#####################  Private functions below ##################################

_he_dyntxt_post() {
  hostname=$1
  txt=$2
  response="$(_post "hostname=$hostname&password=$HE_DynTXT_Key&txt=$txt" "$HE_DynTXT_Api")"

  if [ "$?" != "0" ]; then
    _err "POST failed"
    return 1
  fi
  _debug2 response "$response"

  if _contains "$response" "good" || _contains "$response" "nochg"; then
    _info "Updated, OK"
    return 0
  elif _contains "$response" "badauth"; then
    _err "'$hostname' missing placeholder TXT record, or DDNS key incorrect"
    return 1
  else
    _err "Unknown POST response: $response"
    return 1
  fi
}
