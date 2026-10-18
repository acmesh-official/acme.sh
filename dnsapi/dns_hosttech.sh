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
  fulldomain="$(_idn "$1")"
  txtvalue=$2

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
  if ! _get_zoneid "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"
  _debug _zoneid "$_zoneid"

  _info "Adding record"
  if _hosttech_rest POST "zones/$_zoneid/records" "{\"type\":\"TXT\",\"name\":\"$_sub_domain\",\"text\":\"$txtvalue\",\"ttl\":600}"; then
    if _contains "$_response" "$_sub_domain"; then
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
  fulldomain="$(_idn "$1")"
  txtvalue=$2

  Hosttech_Key="${Hosttech_Key:-$(_readaccountconf_mutable Hosttech_Key)}"
  if [ -z "$Hosttech_Key" ]; then
    Hosttech_Key=""
    _err "You didn't specify a Hosttech api key."
    _err "You can get yours from https://www.myhosttech.eu/user/dns/api"
    return 1
  fi

  _debug "First detect the zoneid"
  if ! _get_zoneid "$fulldomain"; then
    _err "invalid zoneid"
    return 1
  fi

  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"
  _debug _zoneid "$_zoneid"
  _debug _txtvalue "${txtvalue}"

  _debug "Second detect the recordid"
  if ! _get_recordid "$_sub_domain" "$txtvalue"; then
    _err "Error querying records"
    return 1
  fi

  if [ -z "$_recordid" ]; then
    _info "Record not available"
    return 0
  fi

  _debug "Removing txt record"
  if ! _hosttech_rest DELETE "zones/$_zoneid/records/$_recordid"; then
    _err "Cannot remove record"
    return 1
  fi
  _debug "Record removed"
  return 0
}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
# _zoneid=id of the zone domain.com
_get_zoneid() {
  domain=$1
  i=1
  p=1
  while true; do
    _domain=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-"$p")
    _debug _domain "$_domain"
    if [ -z "$_domain" ]; then
      #not valid
      return 1
    fi

    if ! _hosttech_rest GET "zones?query=${_domain}"; then
      return 1
    fi
    # The query is a search and may return several zones, pick the exact match
    _zoneid="$(printf "%s" "$_response" | _egrep_o "\"id\":[0-9]+,\"name\":\"$_domain\"" | _head_n 1 | cut -d : -f 2 | cut -d , -f 1)"
    if [ -n "$_zoneid" ]; then
      return 0
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

#Usage: subdomain txtvalue
#returns
# _recordid=id of the matching TXT record, empty if none
_get_recordid() {
  subdomain=$1
  txtvalue=$2
  _recordid=""

  # Get all dns records for the zone
  if ! _hosttech_rest GET "zones/$_zoneid/records"; then
    return 1
  fi
  _recordid=$(printf "%s" "$_response" | _egrep_o "[^{]*\"name\":\"$subdomain\"[^}]*" | _egrep_o "[^{]*\"text\":\"$txtvalue\"[^}]*" | _egrep_o "\"id\":[0-9]+" | _head_n 1 | cut -d : -f 2)
  _debug _recordid "$_recordid"
  return 0
}

_hosttech_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"

  export _H1="Authorization: Bearer $Hosttech_Key"
  export _H2="accept: application/json"
  export _H3="Content-Type: application/json"

  _debug data "$data"
  if [ "$m" = "GET" ]; then
    if ! _response="$(_get "$Hosttech_Api/$ep")"; then
      _err "error $ep: request failed"
      return 1
    fi
  else
    if ! _response="$(_post "$data" "$Hosttech_Api/$ep" "" "$m")"; then
      _err "error $ep: request failed"
      return 1
    fi
  fi

  _code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\\r\\n")"
  _debug "http response code $_code"

  case "$_code" in
    2??) ;;
    *)
      _err "error $ep: HTTP $_code"
      _debug2 response "$_response"
      return 1
      ;;
  esac

  _debug2 response "$_response"
  return 0
}
