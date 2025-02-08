#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_hosttech_info='hosttech.eu
Site: hosttech.eu
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_hosttech
Options:
 Hosttech_Key API Key
Issues: github.com/acmesh-official/acme.sh/issues/4900
'

#Hosttech_Key="asdfasdfawefasdfawefasdafe"

Hosttech_Api="https://api.ns1.hosttech.eu/api/user/v1"

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_hosttech_add() {
  fulldomain=$1
  txtvalue=$2

  Hosttech_Key="${Hosttech_Key:-$(_readaccountconf_mutable Hosttech_Key)}"
  if [ -z "$Hosttech_Key" ]; then
    Hosttech_Key=""
    _err "You didn't specify a Hosttech api key"
    _err "You can get yours from https://www.myhosttech.eu/user/dns/api"
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _info "Adding record"
  if _hosttech_rest POST "zones/$_domain/records" "{\"type\":\"TXT\",\"name\":\"$_sub_domain\",\"text\":\"$txtvalue\",\"ttl\":600}"; then
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

#fulldomain txtvalue
dns_hosttech_rm() {
  fulldomain=$1
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
  if ! _get_recordid "$_domain" "$_sub_domain" "${txtvalue}"; then
    _err "invalid recordid"
    return 1
  fi
  _debug _recordid "$_recordid"

  _debug "Removing txt record"
  _hosttech_rest DELETE "zones/$_domain/records/$_recordid"
}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
_get_root() {
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

    if _hosttech_rest GET "zones?query=${_domain}"; then
      if [ "$(echo "$_response" | _egrep_o '"name":"[^"]*' | cut -d'"' -f4)" = "${_domain}" ]; then
        return 0
      fi
    else
      return 1
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

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

    if _hosttech_rest GET "zones?query=${_domain}"; then
      if [ "$(echo "$_response" | _egrep_o '"name":"[^"]*' | cut -d'"' -f4)" = "${_domain}" ]; then
        # Get the id of the zone in question
        _zoneid="$(echo "$_response" | _egrep_o '"id":[0-9]*' | cut -d':' -f2)"
        if [ -z "$_zoneid" ]; then
          return 1
        fi
        return 0
      fi
    else
      return 1
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

_get_recordid() {
  domainid=$1
  subdomain=$2
  txtvalue=$3

  # Get all dns records for the domainname
  if _hosttech_rest GET "zones/$_zoneid/records"; then
    if ! _contains "$_response" '"id"'; then
      _debug "No records in dns"
      return 1
    fi
    if ! _contains "$_response" '\"name\":\"'"$subdomain"'\"'; then
      _debug "Record does not exist"
      return 1
    fi
    # Get the id of the record in question
    _recordid=$(printf "%s" "$_response" | _egrep_o "[^{]*\"name\":\"$subdomain\"[^}]*" | _egrep_o "[^{]*\"text\":\"$txtvalue\"[^}]*" | _egrep_o "\"id\":[0-9]+" | cut -d : -f 2)
    if [ -z "$_recordid" ]; then
      return 1
    fi
    return 0
  fi
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
  _response="$(_post "$data" "$Hosttech_Api/$ep" "" "$m")"

  _code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\\r\\n")"
  _debug "http response code $_code"

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi

  _debug2 response "$_response"
  return 0
}
