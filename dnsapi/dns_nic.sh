#!/usr/bin/env sh

#
#NIC_ClientID='0dc0xxxxxxxxxxxxxxxxxxxxxxxxce88'
#NIC_ClientSecret='3LTtxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxnuW8'
#NIC_Username="000000/NIC-D"
#NIC_Password="xxxxxxx"

NIC_Api="https://api.nic.ru"

dns_nic_add() {
  fulldomain="${1}"
  txtvalue="${2}"

  if ! _nic_get_authtoken save; then
    _err "get NIC auth token failed"
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "Invalid domain"
    return 1
  fi

  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"
  _debug _service "$_service"

  _info "Adding record"
  if ! _nic_rest PUT "services/$_service/zones/$_domain/records" "<?xml version=\"1.0\" encoding=\"UTF-8\" ?><request><rr-list><rr><name>$_sub_domain</name><type>TXT</type><txt><string>$txtvalue</string></txt></rr></rr-list></request>"; then
    _err "Add TXT record error"
    return 1
  fi

  if ! _nic_rest POST "services/$_service/zones/$_domain/commit" ""; then
    return 1
  fi
  _info "Added, OK"
}

dns_nic_rm() {
  fulldomain="${1}"
  txtvalue="${2}"

  if ! _nic_get_authtoken; then
    _err "get NIC auth token failed"
    return 1
  fi

  if ! _get_root "$fulldomain"; then
    _err "Invalid domain"
    return 1
  fi

  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"
  _debug _service "$_service"

  if ! _nic_rest GET "services/$_service/zones/$_domain/records"; then
    _err "Get records error"
    return 1
  fi

  _domain_id=$(printf "%s" "$response" | grep "$_sub_domain" | grep -- "$txtvalue" | sed -r "s/.*<rr id=\"(.*)\".*/\1/g")

  if ! _nic_rest DELETE "services/$_service/zones/$_domain/records/$_domain_id"; then
    _err "Delete record error"
    return 1
  fi

  if ! _nic_rest POST "services/$_service/zones/$_domain/commit" ""; then
    return 1
  fi
}

####################  Private functions below ##################################

#_nic_get_auth_elements [need2save]
_nic_get_auth_elements() {
  _need2save=$1

  NIC_ClientID="${NIC_ClientID:-$(_readaccountconf_mutable NIC_ClientID)}"
  NIC_ClientSecret="${NIC_ClientSecret:-$(_readaccountconf_mutable NIC_ClientSecret)}"
  NIC_Username="${NIC_Username:-$(_readaccountconf_mutable NIC_Username)}"
  NIC_Password="${NIC_Password:-$(_readaccountconf_mutable NIC_Password)}"

  ## for backward compatibility
  if [ -z "$NIC_ClientID" ] || [ -z "$NIC_ClientSecret" ]; then
    NIC_Token="${NIC_Token:-$(_readaccountconf_mutable NIC_Token)}"
    _debug NIC_Token "$NIC_Token"
    if [ -n "$NIC_Token" ]; then
      _two_values="$(echo "${NIC_Token}" | _dbase64)"
      _debug _two_values "$_two_values"
      NIC_ClientID=$(echo "$_two_values" | cut -d':' -f1)
      NIC_ClientSecret=$(echo "$_two_values" | cut -d':' -f2-)
      _debug restored_NIC_ClientID "$NIC_ClientID"
      _debug restored_NIC_ClientSecret "$NIC_ClientSecret"
    fi
  fi

  if [ -z "$NIC_ClientID" ] || [ -z "$NIC_ClientSecret" ] || [ -z "$NIC_Username" ] || [ -z "$NIC_Password" ]; then
    NIC_ClientID=""
    NIC_ClientSecret=""
    NIC_Username=""
    NIC_Password=""
    _err "You must export variables: NIC_ClientID, NIC_ClientSecret, NIC_Username and NIC_Password"
    return 1
  fi

  if [ "$_need2save" ]; then
    _saveaccountconf_mutable NIC_ClientID "$NIC_ClientID"
    _saveaccountconf_mutable NIC_ClientSecret "$NIC_ClientSecret"
    _saveaccountconf_mutable NIC_Username "$NIC_Username"
    _saveaccountconf_mutable NIC_Password "$NIC_Password"
  fi

  NIC_BasicAuth=$(printf "%s:%s" "${NIC_ClientID}" "${NIC_ClientSecret}" | _base64)
  _debug NIC_BasicAuth "$NIC_BasicAuth"

}

#_nic_get_authtoken [need2save]
_nic_get_authtoken() {
  _need2save=$1

  if ! _nic_get_auth_elements "$_need2save"; then
    return 1
  fi

  _info "Getting NIC auth token"

  export _H1="Authorization: Basic ${NIC_BasicAuth}"
  export _H2="Content-Type: application/x-www-form-urlencoded"

  res=$(_post "grant_type=password&username=${NIC_Username}&password=${NIC_Password}&scope=%28GET%7CPUT%7CPOST%7CDELETE%29%3A%2Fdns-master%2F.%2B" "$NIC_Api/oauth/token" "" "POST")
  if _contains "$res" "access_token"; then
    _auth_token=$(printf "%s" "$res" | cut -d , -f2 | tr -d "\"" | sed "s/access_token://")
    _info "Token received"
    _debug _auth_token "$_auth_token"
    return 0
  fi
  return 1
}

_get_root() {
  domain="$1"
  i=1
  p=1

  if ! _nic_rest GET "zones"; then
    return 1
  fi

  _all_domains=$(printf "%s" "$response" | grep "idn-name" | sed -r "s/.*idn-name=\"(.*)\" name=.*/\1/g")
  _debug2 _all_domains "$_all_domains"

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    _debug h "$h"

    if [ -z "$h" ]; then
      return 1
    fi

    if _contains "$_all_domains" "^$h$"; then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
      _domain=$h
      _service=$(printf "%s" "$response" | grep -m 1 "idn-name=\"$_domain\"" | sed -r "s/.*service=\"(.*)\".*$/\1/")
      return 0
    fi
    p="$i"
    i=$(_math "$i" + 1)
  done
  return 1
}

_nic_rest() {
  m="$1"
  ep="$2"
  data="$3"
  _debug "$ep"

  export _H1="Content-Type: application/xml"
  export _H2="Authorization: Bearer $_auth_token"

  if [ "$m" != "GET" ]; then
    _debug data "$data"
    response=$(_post "$data" "$NIC_Api/dns-master/$ep" "" "$m")
  else
    response=$(_get "$NIC_Api/dns-master/$ep")
  fi

  if _contains "$response" "<errors>"; then
    error=$(printf "%s" "$response" | grep "error code" | sed -r "s/.*<error code=.*>(.*)<\/error>/\1/g")
    _err "Error: $error"
    return 1
  fi

  if ! _contains "$response" "<status>success</status>"; then
    return 1
  fi
  _debug2 response "$response"
  return 0
}
