#!/usr/bin/env sh

#ISPConfig 3.1 API - Add remote user and give him access to at least the "DNS txt functions"

ISPC_User=""
ISPC_Password=""
ISPC_Api="https://ispc.domain.tld:8080/remote/json.php"  # Provider proper URL and port for your ISPC Installation


########  Public functions #####################

#Usage: dns_myapi_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_ispconfig_add() {
  fulldomain="${1}"
  txtvalue="${2}"
  _ISPC_login
  if [ $? -eq 0 ]; then
    _ISPC_getZoneInfo
  fi
  if [ $? -eq 0 ]; then
    _ISPC_addTxt
  fi
  if [ $? -ne 0 ]; then
    return 1
  fi
}

#Usage: dns_myapi_rm   _acme-challenge.www.domain.com
dns_ispconfig_rm() {
  fulldomain="${1}"
  _ISPC_login
  if [ $? -eq 0 ]; then
    _ISPC_rmTxt
  fi
  if [ $? -ne 0 ]; then
    return 1
  fi
}

####################  Private functions bellow ##################################

_ISPC_login() {
  _info "Getting Session ID"
  curData="{\"username\":\"${ISPC_User}\",\"password\":\"${ISPC_Password}\",\"client_login\":false}"
  curResult=$(curl -k --data "${curData}" "${ISPC_Api}?login")
  if _contains "${curResult}" '"code":"ok"'; then 
    sessionID=$(echo $curResult | _egrep_o "response.*" | cut -d ':' -f 2)
    sessionID=${sessionID:1:-2}
    _info "Successfully retrieved Session ID."
  else
    _err "Couldn't retrieve the Session ID. Aborting.";
  fi
}

_ISPC_getZoneInfo () {
  _info "Getting Zoneinfo"
  zoneEnd=false
  curZone="${fulldomain}"
  while [ ${zoneEnd} = false ]; do
    curZone="${curZone#*.}"         # we can strip the first part of the fulldomain, since it's just the _acme-challenge string
    curData="{\"session_id\":\"${sessionID}\",\"primary_id\":[{\"origin\":\"${curZone}.\"}]}"         # suffix . needed for zone -> domain.tld.
    curResult=$(curl -k --data "${curData}" "${ISPC_Api}?dns_zone_get")
    if _contains "${curResult}" '"id":"'; then
      zoneFound=true
      zoneEnd=true
      _info "Successfully retrieved zone data."
    fi
    if [ "${curZone#*.}" != "$curZone" ]; then
      _debug2 "$curZone still contains a '.' - so we can check next higher level"
    else 
      zoneEnd=true
      _err "Couldn't retrieve zone info. Aborting."
    fi
  done
  if [ ${zoneFound} ]; then
    server_id=$(echo $curResult | _egrep_o "server_id.*" | cut -d ':' -f 2)
    server_id=${server_id:1:-10}
    case ${server_id} in
      ''|*[!0-9]*) _err "Server ID is not numeric. Aborting" ;;
                *) _info "Successfully retrieved Server ID" ;;
    esac
      zone=$(echo $curResult | _egrep_o "\"id.*" | cut -d ':' -f 2)
      zone=${zone:1:-14}
      case ${zone} in
        ''|*[!0-9]*) _err "Zone ID is not numeric. Aborting" ;;
                  *) _info "Successfully retrieved Zone ID" ;;
    esac
    client_id=$(echo $curResult | _egrep_o "sys_userid.*" | cut -d ':' -f 2)
    client_id=${client_id:1:-15}
    case ${client_id} in
      ''|*[!0-9]*) _err "Client ID is not numeric. Aborting" ;;
                *) _info "Successfully retrieved Client ID" ;;
    esac
      unset zoneFound
      unset zoneEnd
  fi
}

_ISPC_addTxt () {
  curSerial="$(date +%s)"
  curStamp="$(date +'%F %T')"
  params="\"server_id\":\"${server_id}\",\"zone\":\"${zone}\",\"name\":\"${fulldomain}\",\"type\":\"txt\",\"data\":\"${txtvalue}\",\"aux\":\"0\",\"ttl\":\"3600\",\"active\":\"y\",\"stamp\":\"${curStamp}\",\"serial\":\"${curSerial}\""
  curData="{\"session_id\":\"${sessionID}\",\"client_id\":\"${client_id}\",\"params\":{${params}}}"
  curResult=$(curl -k --data "${curData}" "${ISPC_Api}?dns_txt_add")
  record_id=$(echo $curResult | _egrep_o "\"response.*" | cut -d ':' -f 2)
  record_id=${record_id:1:-2}
  case ${record_id} in
    ''|*[!0-9]*) _err "Record ID is not numeric. Aborting" ;;
              *) _info "Successfully retrieved Record ID"; 
                 record_data="$record_data $record_id" ;;  # Make space seperated string of record IDs for later removal.
  esac
}

_ISPC_rmTxt () {
  IFS=" "
  for i in $record_data; do
    curData="{\"session_id\":\"${sessionID}\",\"primary_id\":\"${i}\"}"
    curResult=$(curl -k --data "${curData}" "${ISPC_Api}?dns_txt_delete")
    echo $curResult;
    if _contains "${curResult}" '"code":"ok"'; then 
      _info "Successfully removed ACME challenge txt record."
    else
      _debug "Couldn't remove ACME challenge txt record";  # Setting it to debug only because there's no harm if the txt remains
    fi
  done
}
