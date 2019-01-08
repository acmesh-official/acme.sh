#!/usr/bin/env sh

# hosting.de API

# Values to export:
# export HOSTINGDE_ENDPOINT='https://secure.hosting.de'
# export HOSTINGDE_APIKEY='xxxxx'

########  Public functions #####################

dns_hostingde_add() {
  fulldomain="${1}"
  txtvalue="${2}"
  _debug "Calling: _hostingde_addRecord() '${fulldomain}' '${txtvalue}'"
  _hostingde_apiKey && _hostingde_getZoneConfig && _hostingde_addRecord
}

dns_hostingde_rm() {
  fulldomain="${1}"
  txtvalue="${2}"
  _debug "Calling: _hostingde_removeRecord() '${fulldomain}' '${txtvalue}'"
  _hostingde_apiKey && _hostingde_getZoneConfig && _hostingde_removeRecord
}

#################### own Private functions below ##################################

_hostingde_apiKey() {
  HOSTINGDE_APIKEY="${HOSTINGDE_APIKEY:-$(_readaccountconf_mutable HOSTINGDE_APIKEY)}"
  if [ -z "$HOSTINGDE_APIKEY" ] || [ -z "$HOSTINGDE_ENDPOINT" ]; then
    HOSTINGDE_APIKEY=""
    HOSTINGDE_ENDPOINT=""
    _err "You haven't specified hosting.de API key or endpoint yet."
    _err "Please create your key and try again."
    return 1
  fi

  _saveaccountconf_mutable HOSTINGDE_APIKEY "$HOSTINGDE_APIKEY"
  _saveaccountconf_mutable HOSTINGDE_ENDPOINT "$HOSTINGDE_ENDPOINT"
}

_hostingde_getZoneConfig() {
  _info "Getting ZoneConfig"
  curZone="${fulldomain#*.}"
  returnCode=1
  while _contains "${curZone}" "\\."; do
    curData="{\"filter\":{\"field\":\"zoneName\",\"value\":\"${curZone}\"},\"limit\":1,\"authToken\":\"${HOSTINGDE_APIKEY}\"}"
    curResult="$(_post "${curData}" "${HOSTINGDE_ENDPOINT}/api/dns/v1/json/zoneConfigsFind")"
    _debug "Calling zoneConfigsFind: '${curData}' '${HOSTINGDE_ENDPOINT}/api/dns/v1/json/zoneConfigsFind'"
    _debug "Result of zoneConfigsFind: '$curResult'"
    if _contains "${curResult}" '"status": "error"'; then
      if _contains "${curResult}" '"code": 10109'; then
        _err "The API-Key is invalid or could not be found"
      else
        _err "UNKNOWN API ERROR"
      fi
      returnCode=1
      break
    fi
    if _contains "${curResult}" '"totalEntries": 1'; then
      _info "Retrieved zone data."
      _debug "Zone data: '${curResult}'"

      # read ZoneConfigId for later update
      zoneConfigId=$(echo "${curResult}" | _egrep_o '"id":.*' | cut -d ':' -f 2 | cut -d '"' -f 2)
      _debug "zoneConfigId '${zoneConfigId}'"
      returnCode=0
      break
    fi
    curZone="${curZone#*.}"
  done
  if [ $returnCode -ne 0 ]; then
    _info "ZoneEnd reached, Zone ${curZone} not found in hosting.de API"
  fi
  return $returnCode
}

_hostingde_getZoneStatus() {
  _debug "Checking Zone status"
  curData="{\"filter\":{\"field\":\"zoneConfigId\",\"value\":\"${zoneConfigId}\"},\"limit\":1,\"authToken\":\"${HOSTINGDE_APIKEY}\"}"
  curResult="$(_post "${curData}" "${HOSTINGDE_ENDPOINT}/api/dns/v1/json/zonesFind")"
  _debug "Calling zonesFind '${curData}' '${HOSTINGDE_ENDPOINT}/api/dns/v1/json/zonesFind'"
  _debug "Result of zonesFind '$curResult'"
  zoneStatus=$(echo "${curResult}" | grep -v success | _egrep_o '"status":.*' | cut -d ':' -f 2 | cut -d '"' -f 2)
  _debug "zoneStatus '${zoneStatus}'"
  return 0
}

_hostingde_addRecord() {
  _info "Adding record to zone"
  _hostingde_getZoneStatus
  _debug "Result of zoneStatus: '${zoneStatus}'"
  while [ "${zoneStatus}" != "active" ]; do
    _sleep 5
    _hostingde_getZoneStatus
    _debug "Result of zoneStatus: '${zoneStatus}'"
  done
  curData="{\"authToken\":\"${HOSTINGDE_APIKEY}\",\"zoneConfig\":{\"id\":\"${zoneConfigId}\"},\"recordsToAdd\":[{\"name\":\"${fulldomain}\",\"type\":\"TXT\",\"content\":\"\\\"${txtvalue}\\\"\",\"ttl\":3600}]}"
  curResult="$(_post "${curData}" "${HOSTINGDE_ENDPOINT}/api/dns/v1/json/zoneUpdate")"
  _debug "Calling zoneUpdate: '${curData}' '${HOSTINGDE_ENDPOINT}/api/dns/v1/json/zoneUpdate'"
  _debug "Result of zoneUpdate: '$curResult'"
  if _contains "${curResult}" '"status": "error"'; then
    if _contains "${curResult}" '"code": 10109'; then
      _err "The API-Key is invalid or could not be found"
    else
      _err "UNKNOWN API ERROR"
    fi
    return 1
  fi
  return 0
}

_hostingde_removeRecord() {
  _info "Removing record from zone"
  _hostingde_getZoneStatus
  _debug "Result of zoneStatus: '$zoneStatus'"
  while [ "$zoneStatus" != "active" ]; do
    _sleep 5
    _hostingde_getZoneStatus
    _debug "Result of zoneStatus: '$zoneStatus'"
  done
  curData="{\"authToken\":\"${HOSTINGDE_APIKEY}\",\"zoneConfig\":{\"id\":\"${zoneConfigId}\"},\"recordsToDelete\":[{\"name\":\"${fulldomain}\",\"type\":\"TXT\",\"content\":\"\\\"${txtvalue}\\\"\"}]}"
  curResult="$(_post "${curData}" "${HOSTINGDE_ENDPOINT}/api/dns/v1/json/zoneUpdate")"
  _debug "Calling zoneUpdate: '${curData}' '${HOSTINGDE_ENDPOINT}/api/dns/v1/json/zoneUpdate'"
  _debug "Result of zoneUpdate: '$curResult'"
  if _contains "${curResult}" '"status": "error"'; then
    if _contains "${curResult}" '"code": 10109'; then
      _err "The API-Key is invalid or could not be found"
    else
      _err "UNKNOWN API ERROR"
    fi
    return 1
  fi
  return 0
}
