#!/usr/bin/env sh

# ISPConfig 3.1 API
# User must provide login data and URL to the ISPConfig installation incl. port. The remote user in ISPConfig must have access to:
# - DNS txt Functions

# Report bugs to https://github.com/sjau/acme.sh

# Values to export:
# export ISPC_User="remoteUser"
# export ISPC_Password="remotePassword"
# export ISPC_Api="https://ispc.domain.tld:8080/remote/json.php"
# export ISPC_Api_Insecure=1     # Set 1 for insecure and 0 for secure -> difference is whether ssl cert is checked for validity (0) or whether it is just accepted (1)

########  Public functions #####################

#Usage: dns_myapi_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_ispconfig_add() {
  fulldomain="${1}"
  txtvalue="${2}"
  _debug "Calling: dns_ispconfig_add() '${fulldomain}' '${txtvalue}'"
  _ISPC_credentials && _ISPC_login && _ISPC_getZoneInfo && _ISPC_addTxt
}

#Usage: dns_myapi_rm   _acme-challenge.www.domain.com
dns_ispconfig_rm() {
  fulldomain="${1}"
  _debug "Calling: dns_ispconfig_rm() '${fulldomain}'"
  _ISPC_credentials && _ISPC_login && _ISPC_rmTxt
}

####################  Private functions below ##################################

_ISPC_credentials() {
  if [ -z "${ISPC_User}" ] || [ -z "$ISPC_Password" ] || [ -z "${ISPC_Api}" ] || [ -z "${ISPC_Api_Insecure}" ]; then
    ISPC_User=""
    ISPC_Password=""
    ISPC_Api=""
    ISPC_Api_Insecure=""
    _err "You haven't specified the ISPConfig Login data, URL and whether you want check the ISPC SSL cert. Please try again."
    return 1
  else
    _saveaccountconf ISPC_User "${ISPC_User}"
    _saveaccountconf ISPC_Password "${ISPC_Password}"
    _saveaccountconf ISPC_Api "${ISPC_Api}"
    _saveaccountconf ISPC_Api_Insecure "${ISPC_Api_Insecure}"
    # Set whether curl should use secure or insecure mode
    export HTTPS_INSECURE="${ISPC_Api_Insecure}"
  fi
}

_ISPC_login() {
  _info "Getting Session ID"
  curData="{\"username\":\"${ISPC_User}\",\"password\":\"${ISPC_Password}\",\"client_login\":false}"
  curResult="$(_post "${curData}" "${ISPC_Api}?login")"
  _debug "Calling _ISPC_login: '${curData}' '${ISPC_Api}?login'"
  _debug "Result of _ISPC_login: '$curResult'"
  if _contains "${curResult}" '"code":"ok"'; then
    sessionID=$(echo "${curResult}" | _egrep_o "response.*" | cut -d ':' -f 2 | cut -d '"' -f 2)
    _info "Retrieved Session ID."
    _debug "Session ID: '${sessionID}'"
  else
    _err "Couldn't retrieve the Session ID."
    return 1
  fi
}

_ISPC_getZoneInfo() {
  _info "Getting Zoneinfo"
  zoneEnd=false
  curZone="${fulldomain}"
  while [ "${zoneEnd}" = false ]; do
    # we can strip the first part of the fulldomain, since it's just the _acme-challenge string
    curZone="${curZone#*.}"
    # suffix . needed for zone -> domain.tld.
    curData="{\"session_id\":\"${sessionID}\",\"primary_id\":{\"origin\":\"${curZone}.\"}}"
    curResult="$(_post "${curData}" "${ISPC_Api}?dns_zone_get")"
    _debug "Calling _ISPC_getZoneInfo: '${curData}' '${ISPC_Api}?dns_zone_get'"
    _debug "Result of _ISPC_getZoneInfo: '$curResult'"
    if _contains "${curResult}" '"id":"'; then
      zoneFound=true
      zoneEnd=true
      _info "Retrieved zone data."
      _debug "Zone data: '${curResult}'"
    fi
    if [ "${curZone#*.}" != "$curZone" ]; then
      _debug2 "$curZone still contains a '.' - so we can check next higher level"
    else
      zoneEnd=true
      _err "Couldn't retrieve zone data."
      return 1
    fi
  done
  if [ "${zoneFound}" ]; then
    server_id=$(echo "${curResult}" | _egrep_o "server_id.*" | cut -d ':' -f 2 | cut -d '"' -f 2)
    _debug "Server ID: '${server_id}'"
    case "${server_id}" in
    '' | *[!0-9]*)
      _err "Server ID is not numeric."
      return 1
      ;;
    *) _info "Retrieved Server ID" ;;
    esac
    zone=$(echo "${curResult}" | _egrep_o "\"id.*" | cut -d ':' -f 2 | cut -d '"' -f 2)
    _debug "Zone: '${zone}'"
    case "${zone}" in
    '' | *[!0-9]*)
      _err "Zone ID is not numeric."
      return 1
      ;;
    *) _info "Retrieved Zone ID" ;;
    esac
    sys_userid=$(echo "${curResult}" | _egrep_o "sys_userid.*" | cut -d ':' -f 2 | cut -d '"' -f 2)
    _debug "SYS User ID: '${sys_userid}'"
    case "${sys_userid}" in
    '' | *[!0-9]*)
      _err "SYS User ID is not numeric."
      return 1
      ;;
    *) _info "Retrieved SYS User ID." ;;
    esac
    zoneFound=""
    zoneEnd=""
  fi
  # Need to get client_id as it is different from sys_userid
  curData="{\"session_id\":\"${sessionID}\",\"sys_userid\":\"${sys_userid}\"}"
  curResult="$(_post "${curData}" "${ISPC_Api}?client_get_id")"
  _debug "Calling _ISPC_ClientGetID: '${curData}' '${ISPC_Api}?client_get_id'"
  _debug "Result of _ISPC_ClientGetID: '$curResult'"
  client_id=$(echo "${curResult}" | _egrep_o "response.*" | cut -d ':' -f 2 | cut -d '"' -f 2 | tr -d '{}')
  _debug "Client ID: '${client_id}'"
  case "${client_id}" in
  '' | *[!0-9]*)
    _err "Client ID is not numeric."
    return 1
    ;;
  *) _info "Retrieved Client ID." ;;
  esac
}

_ISPC_addTxt() {
  curSerial="$(date +%s)"
  curStamp="$(date +'%F %T')"
  params="\"server_id\":\"${server_id}\",\"zone\":\"${zone}\",\"name\":\"${fulldomain}.\",\"type\":\"txt\",\"data\":\"${txtvalue}\",\"aux\":\"0\",\"ttl\":\"3600\",\"active\":\"y\",\"stamp\":\"${curStamp}\",\"serial\":\"${curSerial}\""
  curData="{\"session_id\":\"${sessionID}\",\"client_id\":\"${client_id}\",\"params\":{${params}},\"update_serial\":true}"
  curResult="$(_post "${curData}" "${ISPC_Api}?dns_txt_add")"
  _debug "Calling _ISPC_addTxt: '${curData}' '${ISPC_Api}?dns_txt_add'"
  _debug "Result of _ISPC_addTxt: '$curResult'"
  record_id=$(echo "${curResult}" | _egrep_o "\"response.*" | cut -d ':' -f 2 | cut -d '"' -f 2)
  _debug "Record ID: '${record_id}'"
  case "${record_id}" in
  '' | *[!0-9]*)
    _err "Couldn't add ACME Challenge TXT record to zone."
    return 1
    ;;
  *) _info "Added ACME Challenge TXT record to zone." ;;
  esac
}

_ISPC_rmTxt() {
  # Need to get the record ID.
  curData="{\"session_id\":\"${sessionID}\",\"primary_id\":{\"name\":\"${fulldomain}.\",\"type\":\"TXT\"}}"
  curResult="$(_post "${curData}" "${ISPC_Api}?dns_txt_get")"
  _debug "Calling _ISPC_rmTxt: '${curData}' '${ISPC_Api}?dns_txt_get'"
  _debug "Result of _ISPC_rmTxt: '$curResult'"
  if _contains "${curResult}" '"code":"ok"'; then
    record_id=$(echo "${curResult}" | _egrep_o "\"id.*" | cut -d ':' -f 2 | cut -d '"' -f 2)
    _debug "Record ID: '${record_id}'"
    case "${record_id}" in
    '' | *[!0-9]*)
      _err "Record ID is not numeric."
      return 1
      ;;
    *)
      unset IFS
      _info "Retrieved Record ID."
      curData="{\"session_id\":\"${sessionID}\",\"primary_id\":\"${record_id}\",\"update_serial\":true}"
      curResult="$(_post "${curData}" "${ISPC_Api}?dns_txt_delete")"
      _debug "Calling _ISPC_rmTxt: '${curData}' '${ISPC_Api}?dns_txt_delete'"
      _debug "Result of _ISPC_rmTxt: '$curResult'"
      if _contains "${curResult}" '"code":"ok"'; then
        _info "Removed ACME Challenge TXT record from zone."
      else
        _err "Couldn't remove ACME Challenge TXT record from zone."
        return 1
      fi
      ;;
    esac
  fi
}
