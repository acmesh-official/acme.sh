#!/usr/bin/env sh

# 
# facileManager (https://github.com/WillyXJ/facileManager) hook script for acme.sh
#
# Author: Gianluca Giacometti
# Git repo and usage: https://github.com/gianlucagiacometti/proxmox-acme-facilemanager
#

# Values to export:
# export FMDNS_API_ENDPOINT='https://my.fmdnsapi.endpoint'
# export FMDNS_API_TOKEN='xxxxx'
# export FMDNS_API_DOMAIN_ID='xxxxx'

# IMPORTANT NOTE: set the validation delay at a minimum value of 360s, since facileManager usually updates dns zones every 300s

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
  curData="{\"fmAuthToken\":\"${FMDNS_API_TOKEN}\",\"id\":\"${FMDNS_API_DOMAIN_ID}\",\"action\":\"add\",\"name\":\"${fulldomain}\",\"value\":\"${txtvalue}\",\"type\":\"TXT\",\"ttl\":\"5\",\"autoupdate\":\"yes\"}"
  curResult="$(_post "${curData}" "${FMDNS_API_ENDPOINT}")"
  _info "API result: "${curResult}""
  _debug "Calling facileManager API: '${curData}' '${FMDNS_API_ENDPOINT}'"
  _debug "Result of zone add: '$curResult'"
  if [ "${curResult}" != "Success" ]; then
    if [ -z "${curResult}" ]; then
      _err "Empty response"
    else
      _err "${curResult}"
    fi
    return 1
  fi
  return 0
}

_fmDnsApi_removeRecord() {
  _info "Connecting to ${FMDNS_API_ENDPOINT}"
  _info "Removing record from zone"
  curData="{\"fmAuthToken\":\"${FMDNS_API_TOKEN}\",\"id\":\"${FMDNS_API_DOMAIN_ID}\",\"action\":\"delete\",\"name\":\"${fulldomain}\",\"type\":\"TXT\",\"ttl\":\"5\",\"autoupdate\":\"yes\"}"
  curResult="$(_post "${curData}" "${FMDNS_API_ENDPOINT}")"
  _info "API result: "${curResult}""
  _debug "Calling facileManager API: '${curData}' '${FMDNS_API_ENDPOINT}'"
  _debug "Result of zone delete: '$curResult'"
  if [ "${curResult}" != "Success" ]; then
    if [ -z "${curResult}" ]; then
      _err "Empty response"
    else
      _err "${curResult}"
    fi
    return 1
  fi
  return 0
}
