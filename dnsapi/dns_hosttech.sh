#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_hosttech_info='hosttech.eu
Site: hosttech.eu
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_hosttech
Options:
 Hosttech_Key API Key
Issues: github.com/acmesh-official/acme.sh/issues/4900
'

Hosttech_Api="https://api.ns1.hosttech.eu/api/user/v1"

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
# Used to add txt record
dns_hosttech_add() {
  _hosttech_fulldomain="$(_idn "$1")"
  _hosttech_txtvalue=$2

  Hosttech_Key="${Hosttech_Key:-$(_readaccountconf_mutable Hosttech_Key)}"
  if [ -z "$Hosttech_Key" ]; then
    Hosttech_Key=""
    _err "You didn't specify a Hosttech api key"
    _err "You can get yours from https://www.myhosttech.eu/user/dns/api"
    return 1
  fi

  #save the credentials to the account conf file.
  _saveaccountconf_mutable Hosttech_Key "$Hosttech_Key"

  _debug "First detect the zoneid"
  if ! _hosttech_get_zoneid "$_hosttech_fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _hosttech_sub_domain "$_hosttech_sub_domain"
  _debug _hosttech_domain "$_hosttech_domain"
  _debug _hosttech_zoneid "$_hosttech_zoneid"

  _info "Adding record"
  if _hosttech_rest POST "zones/$_hosttech_zoneid/records" "{\"type\":\"TXT\",\"name\":\"$_hosttech_sub_domain\",\"text\":\"$_hosttech_txtvalue\",\"ttl\":600}"; then
    if _contains "$_hosttech_response" "$_hosttech_txtvalue"; then
      _info "Added, OK"
      return 0
    else
      _err "Add txt record error."
      return 1
    fi
  fi
  _err "Add txt record error."
  return 1
}

# Usage: fulldomain txtvalue
# Used to remove the txt record after validation
dns_hosttech_rm() {
  _hosttech_fulldomain="$(_idn "$1")"
  _hosttech_txtvalue=$2

  Hosttech_Key="${Hosttech_Key:-$(_readaccountconf_mutable Hosttech_Key)}"
  if [ -z "$Hosttech_Key" ]; then
    Hosttech_Key=""
    _err "You didn't specify a Hosttech api key."
    _err "You can get yours from https://www.myhosttech.eu/user/dns/api"
    return 1
  fi

  _debug "First detect the zoneid"
  if ! _hosttech_get_zoneid "$_hosttech_fulldomain"; then
    _err "invalid zoneid"
    return 1
  fi

  _debug _hosttech_sub_domain "$_hosttech_sub_domain"
  _debug _hosttech_domain "$_hosttech_domain"
  _debug _hosttech_zoneid "$_hosttech_zoneid"
  _debug _hosttech_txtvalue "${_hosttech_txtvalue}"

  _debug "Second detect the recordid"
  if ! _hosttech_get_recordid "$_hosttech_sub_domain" "$_hosttech_txtvalue"; then
    _err "Error querying records"
    return 1
  fi

  if [ -z "$_hosttech_recordid" ]; then
    _info "Record not available"
    return 0
  fi

  _debug "Removing txt record"
  if ! _hosttech_rest DELETE "zones/$_hosttech_zoneid/records/$_hosttech_recordid"; then
    _err "Cannot remove record"
    return 1
  fi
  _debug "Record removed"
  return 0
}

####################  Private functions below ##################################

#_acme-challenge.www.domain.com
#returns
# _hosttech_sub_domain=_acme-challenge.www
# _hosttech_domain=domain.com
# _hosttech_zoneid=id of the zone domain.com
_hosttech_get_zoneid() {
  _hosttech_name=$1
  _hosttech_i=1
  _hosttech_p=0
  while true; do
    _hosttech_domain=$(printf "%s" "$_hosttech_name" | cut -d . -f "$_hosttech_i"-100)
    if [ "$_hosttech_p" -gt 0 ]; then
      _hosttech_sub_domain=$(printf "%s" "$_hosttech_name" | cut -d . -f 1-"$_hosttech_p")
    else
      # record at the zone apex
      _hosttech_sub_domain=""
    fi
    _debug _hosttech_domain "$_hosttech_domain"
    if [ -z "$_hosttech_domain" ]; then
      #not valid
      return 1
    fi

    if ! _hosttech_rest GET "zones?query=${_hosttech_domain}"; then
      return 1
    fi
    # The query is a search and may return several zones, pick the exact match
    _hosttech_zoneid="$(printf "%s" "$_hosttech_response" | _egrep_o "\"id\":[0-9]+,\"name\":\"$_hosttech_domain\"" | _head_n 1 | cut -d : -f 2 | cut -d , -f 1)"
    if [ -n "$_hosttech_zoneid" ]; then
      return 0
    fi
    _hosttech_p=$_hosttech_i
    _hosttech_i=$(_math "$_hosttech_i" + 1)
  done
  return 1
}

#Usage: subdomain txtvalue
#returns
# _hosttech_recordid=id of the matching TXT record, empty if none
_hosttech_get_recordid() {
  _hosttech_subdomain=$1
  _hosttech_rr_text=$2
  _hosttech_recordid=""

  # Get all dns records for the zone
  if ! _hosttech_rest GET "zones/$_hosttech_zoneid/records"; then
    return 1
  fi
  if [ -z "$_hosttech_subdomain" ]; then
    # apex records: the API returns "name":null for records it created, "" for others
    _hosttech_name_re='(""|null)'
  else
    _hosttech_name_re="\"$_hosttech_subdomain\""
  fi
  _hosttech_recordid=$(printf "%s" "$_hosttech_response" | _egrep_o "[^{]*\"name\":${_hosttech_name_re}[^}]*" | _egrep_o "[^{]*\"text\":\"$_hosttech_rr_text\"[^}]*" | _egrep_o "\"id\":[0-9]+" | _head_n 1 | cut -d : -f 2)
  _debug _hosttech_recordid "$_hosttech_recordid"
  return 0
}

_hosttech_rest() {
  _hosttech_m=$1
  _hosttech_ep="$2"
  _hosttech_data="$3"
  _debug "$_hosttech_ep"

  export _H1="Authorization: Bearer $Hosttech_Key"
  export _H2="accept: application/json"
  export _H3="Content-Type: application/json"

  _debug data "$_hosttech_data"
  if [ "$_hosttech_m" = "GET" ]; then
    if ! _hosttech_response="$(_get "$Hosttech_Api/$_hosttech_ep")"; then
      _err "error $_hosttech_ep: request failed"
      return 1
    fi
  else
    if ! _hosttech_response="$(_post "$_hosttech_data" "$Hosttech_Api/$_hosttech_ep" "" "$_hosttech_m")"; then
      _err "error $_hosttech_ep: request failed"
      return 1
    fi
  fi

  _hosttech_code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\\r\\n")"
  _debug "http response code $_hosttech_code"

  case "$_hosttech_code" in
  2??) ;;
  *)
    _err "error $_hosttech_ep: HTTP $_hosttech_code"
    _debug2 response "$_hosttech_response"
    return 1
    ;;
  esac

  _debug2 response "$_hosttech_response"
  return 0
}
