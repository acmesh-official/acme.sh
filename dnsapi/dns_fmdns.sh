#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_fmdns_info='facileManager DNS API
 API for self-hosted facileManager DNS github.com/WillyXJ/facileManager
Site: github.com/gianlucagiacometti/proxmox-acme-facilemanager
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_fmdns
Options:
 FMDNS_API_ENDPOINT API Endpoint. Web address of the API endpoint. 
 FMDNS_API_TOKEN API Token.
 FMDNS_API_DOMAIN_ID Domain ID. Domain ID in your facileManager database.
Issues: github.com/gianlucagiacometti/proxmox-acme-facilemanager
Author: Gianluca Giacometti <php@gianlucagiacometti.it>
'

#####################  Public functions #####################

dns_fmdns_add() {
  fulldomain="${1}"
  txtvalue="${2}"

  FMDNS_API_TOKEN="${FMDNS_API_TOKEN:-$(_readaccountconf_mutable FMDNS_API_TOKEN)}"
  # Check if API token exists
  if [ -z "$FMDNS_API_TOKEN" ]; then
    FMDNS_API_TOKEN=""
    _err "You did not specify facileManager API token."
    _err "Please export FMDNS_API_TOKEN and try again."
    return 1
  fi

  FMDNS_API_ENDPOINT="${FMDNS_API_ENDPOINT:-$(_readaccountconf_mutable FMDNS_API_ENDPOINT)}"
  # Check if API endpoint exists
  if [ -z "$FMDNS_API_ENDPOINT" ]; then
    FMDNS_API_ENDPOINT=""
    _err "You did not specify facileManager API endpoint."
    _err "Please export FMDNS_API_ENDPOINT and try again."
    return 1
  fi

  FMDNS_API_DOMAIN_ID="${FMDNS_API_DOMAIN_ID:-$(_readaccountconf_mutable FMDNS_API_DOMAIN_ID)}"
  # Check if API domain id exists
  if [ -z "$FMDNS_API_DOMAIN_ID" ]; then
    FMDNS_API_DOMAIN_ID=""
    _err "You did not specify facileManager API domain id."
    _err "Please export FMDNS_API_DOMAIN_ID and try again."
    return 1
  fi

  _debug "Calling: _fmDnsApi_addRecord() '${fulldomain}' '${txtvalue}'"
  _fmDnsApi_addRecord
  return $?
}

dns_fmdns_rm() {
  fulldomain="${1}"
  txtvalue="${2}"

  FMDNS_API_TOKEN="${FMDNS_API_TOKEN:-$(_readaccountconf_mutable FMDNS_API_TOKEN)}"
  # Check if API token exists
  if [ -z "$FMDNS_API_TOKEN" ]; then
    FMDNS_API_TOKEN=""
    _err "You did not specify facileManager API token."
    _err "Please export FMDNS_API_TOKEN and try again."
    return 1
  fi

  FMDNS_API_ENDPOINT="${FMDNS_API_ENDPOINT:-$(_readaccountconf_mutable FMDNS_API_ENDPOINT)}"
  # Check if API endpoint exists
  if [ -z "$FMDNS_API_ENDPOINT" ]; then
    FMDNS_API_ENDPOINT=""
    _err "You did not specify facileManager API endpoint."
    _err "Please export FMDNS_API_ENDPOINT and try again."
    return 1
  fi

  FMDNS_API_DOMAIN_ID="${FMDNS_API_DOMAIN_ID:-$(_readaccountconf_mutable FMDNS_API_DOMAIN_ID)}"
  # Check if API domain id exists
  if [ -z "$FMDNS_API_DOMAIN_ID" ]; then
    FMDNS_API_DOMAIN_ID=""
    _err "You did not specify facileManager API domain id."
    _err "Please export FMDNS_API_DOMAIN_ID and try again."
    return 1
  fi

  _debug "Calling: _fmDnsApi_removeRecord() '${fulldomain}' '${txtvalue}'"
  _fmDnsApi_removeRecord
  return $?
}

#####################  Private functions #####################

_fmDnsApi_addRecord() {
  _info "Connecting to ${FMDNS_API_ENDPOINT}"
  _info "Adding record to zone"
  curData="{\"fmAuthToken\":\"${FMDNS_API_TOKEN}\",\"id\":\"${FMDNS_API_DOMAIN_ID}\",\"action\":\"add\",\"name\":\"${fulldomain}\",\"value\":\"${txtvalue}\",\"type\":\"TXT\",\"ttl\":\"5\",\"reload\":\"yes\"}"
  curResult="$(_post "${curData}" "${FMDNS_API_ENDPOINT}")"
  _info "API $curResult"
  _debug "Calling facileManager API: '${curData}' '${FMDNS_API_ENDPOINT}'"
  _debug "Result of zone add: '$curResult'"
  if ! _contains "$curResult" 'Success'; then
    if [ -z "$curResult" ]; then
      _err "Empty response"
    else
      _err "$curResult"
    fi
    return 1
  fi
  return 0
}

_fmDnsApi_removeRecord() {
  _info "Connecting to ${FMDNS_API_ENDPOINT}"
  _info "Removing record from zone"
  curData="{\"fmAuthToken\":\"${FMDNS_API_TOKEN}\",\"id\":\"${FMDNS_API_DOMAIN_ID}\",\"action\":\"delete\",\"name\":\"${fulldomain}\",\"type\":\"TXT\",\"ttl\":\"5\",\"reload\":\"yes\"}"
  curResult="$(_post "${curData}" "${FMDNS_API_ENDPOINT}")"
  _info "API $curResult"
  _debug "Calling facileManager API: '${curData}' '${FMDNS_API_ENDPOINT}'"
  _debug "Result of zone delete: '$curResult'"
  if ! _contains "$curResult" 'Success'; then
    if [ -z "$curResult" ]; then
      _err "Empty response"
    else
      _err "$curResult"
    fi
    return 1
  fi
  return 0
}
