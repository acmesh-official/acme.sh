#!/usr/bin/env sh
#
# Author: Fan Jiang
# Author: Wolfgang Ebner
# Author: Sven Neubuaer
#
# Usage:
# export CFPROXY_BASE_URL="https://auth.acme-dns.io"
# export CFPROXY_USERNAME="<username>"
# export CFPROXY_KEY="<key>"
# export CFPROXY_ZONE="<zone>"
#

#Usage: dns_cfproxy_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
# Used to add txt record
dns_cfproxy_add() {
  fulldomain=$1
  txtvalue=$2
  _info "Using cloudflare-proxy"
  _debug "fulldomain $fulldomain"
  _debug "txtvalue $txtvalue"

  CFPROXY_USERNAME="${CFPROXY_USERNAME:-$(_readaccountconf_mutable CFPROXY_USERNAME)}"
  _clearaccountconf_mutable CFPROXY_USERNAME
  CFPROXY_KEY="${CFPROXY_KEY:-$(_readaccountconf_mutable CFPROXY_KEY)}"
  _clearaccountconf_mutable CFPROXY_KEY

  CFPROXY_BASE_URL="${CFPROXY_BASE_URL:-$(_readdomainconf CFPROXY_BASE_URL)}"
  CFPROXY_ZONE="${CFPROXY_ZONE:-$(_readdomainconf CFPROXY_ZONE)}"
  CFPROXY_USERNAME="${CFPROXY_USERNAME:-$(_readdomainconf CFPROXY_USERNAME)}"
  CFPROXY_KEY="${CFPROXY_KEY:-$(_readdomainconf CFPROXY_KEY)}"

  if [ -z "$CFPROXY_BASE_URL" ]; then
    _err "You didn't specify \"CFPROXY_BASE_URL\" token."
    return 1
  fi

  if [ -z "$CFPROXY_ZONE" ]; then
    _err "You didn't specify \"CFPROXY_ZONE\" token."
    return 1
  fi

  if [ -z "$CFPROXY_USERNAME" ]; then
    _err "You didn't specify \"CFPROXY_USERNAME\" token."
    return 1
  fi

  if [ -z "$CFPROXY_KEY" ]; then
    _err "You didn't specify \"CFPROXY_KEY\" token."
    return 1
  fi

  CFPROXY_ADD_URL="$CFPROXY_BASE_URL/add"

  _savedomainconf CFPROXY_BASE_URL "$CFPROXY_BASE_URL"
  _savedomainconf CFPROXY_ZONE "$CFPROXY_ZONE"
  _savedomainconf CFPROXY_USERNAME "$CFPROXY_USERNAME"
  _savedomainconf CFPROXY_KEY "$CFPROXY_KEY"

  export _H1="Accept: application/json"
  export _H2="Content-Type: application/json"
  data="{\"user\":\"$CFPROXY_USERNAME\",\"key\":\"$CFPROXY_KEY\",\"zone\":\"$CFPROXY_ZONE\",\"rec\":\"$fulldomain\",\"rectype\":\"TXT\", \"value\":\"$txtvalue\"}"
  _debug data "$data"
  response="$(_post "$data" "$CFPROXY_ADD_URL" "" "POST")"
  _debug response "$response"

  if ! echo "$response" | grep "\"success\":true" >/dev/null; then
    _err "invalid response of acme-dns"
    return 1
  fi

}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_cfproxy_rm() {
  fulldomain=$1
  txtvalue=$2
  _info "Using acme-dns"
  _debug "fulldomain $fulldomain"
  _debug "txtvalue $txtvalue"

  CFPROXY_USERNAME="${CFPROXY_USERNAME:-$(_readaccountconf_mutable CFPROXY_USERNAME)}"
  _clearaccountconf_mutable CFPROXY_USERNAME
  CFPROXY_KEY="${CFPROXY_KEY:-$(_readaccountconf_mutable CFPROXY_KEY)}"
  _clearaccountconf_mutable CFPROXY_KEY

  CFPROXY_BASE_URL="${CFPROXY_BASE_URL:-$(_readdomainconf CFPROXY_BASE_URL)}"
  CFPROXY_ZONE="${CFPROXY_ZONE:-$(_readdomainconf CFPROXY_ZONE)}"
  CFPROXY_USERNAME="${CFPROXY_USERNAME:-$(_readdomainconf CFPROXY_USERNAME)}"
  CFPROXY_KEY="${CFPROXY_KEY:-$(_readdomainconf CFPROXY_KEY)}"

  CFPROXY_DELETE_URL="$CFPROXY_BASE_URL/delete"

  export _H1="Accept: application/json"
  export _H2="Content-Type: application/json"
  data="{\"user\":\"$CFPROXY_USERNAME\",\"key\":\"$CFPROXY_KEY\",\"zone\":\"$CFPROXY_ZONE\",\"rec\":\"$fulldomain\",\"rectype\":\"TXT\", \"value\":\"$txtvalue\"}"
  _debug data "$data"
  response="$(_post "$data" "$CFPROXY_DELETE_URL" "" "POST")"
  _debug response "$response"

  if ! echo "$response" | grep "\"success\":true" >/dev/null; then
    _err "invalid response of acme-dns"
    return 1
  fi

}

####################  Private functions below ##################################
