#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_ipprojects_info='IP-Projects DNS
Site: ip-projects.de/
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_ipprojects
Options:
 IPP_Apikey API Key
Issues: github.com/acmesh-official/acme.sh/issues/6958
Author: Markus Ebner
'

IPP_Apikey="${IPP_Apikey:-$(_readaccountconf_mutable IPP_Apikey)}"
IPP_API="https://api.ip-projects.de/v1/dns/acme"

########  Public functions  ########

dns_ipprojects_add() {
  fulldomain="$1"
  txtvalue="$2"

  _info "Using IP-Projects DNS API to add record"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  if ! _IPP_load_credentials; then
    return 1
  fi

  _IPP_api_request "add" "$fulldomain" "$txtvalue"
}

dns_ipprojects_rm() {
  fulldomain="$1"
  txtvalue="$2"

  _info "Using IP-Projects DNS API to remove record"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  if ! _IPP_load_credentials; then
    return 1
  fi

  _IPP_api_request "remove" "$fulldomain" "$txtvalue"
}

########  Private helpers  ########

_IPP_load_credentials() {
  IPP_Apikey="${IPP_Apikey:-$(_readaccountconf_mutable IPP_Apikey)}"

  if [ -z "$IPP_Apikey" ]; then
    _err "You must export IPP_Apikey"
    _err "e.g.: export IPP_Apikey=\"your_api_key\""
    return 1
  fi

  _saveaccountconf_mutable IPP_Apikey "$IPP_Apikey"
  return 0
}

_IPP_api_request() {
  action="$1"
  domain="$2"
  value="$3"

  url="$IPP_API/$action"

  data="{\"domain\":\"$domain\",\"key\":\"$domain\",\"value\":\"$value\"}"
  _debug url "$url"
  _debug data "$data"
  export _H1="X-API-Key: $IPP_Apikey"

  response="$(_post "$data" "$url" "" "POST" "application/json")"
  ret="$?"
  _ipprojects_last_http_code=$(grep "^HTTP" "${HTTP_HEADER}" | _tail_n 1 | cut -d " " -f 2 | tr -d '\r\n')

  _debug response "$response"

  if [ "$ret" != "0" ]; then
    _err "HTTP request failed"
    return 1
  fi

  if [ "$_ipprojects_last_http_code" != "200" ]; then
    _err "API returned an error [code: ${_ipprojects_last_http_code}]"
    return 1
  fi

  return 0
}
