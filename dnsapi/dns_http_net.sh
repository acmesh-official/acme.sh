#!/bin/bash

#Author: Roy Kaldung
#Created 06/4/2018
#Utilize http.net API to finish dns-01 verifications.

# HTTP_NET_AUTHTOKEN=yourtoken

HTTP_NET_API="https://partner.http.net/api/dns/v1/json"

dns_http_net_add() {
  fulldomain=$1
  txtvalue=$2

  HTTP_NET_AUTHTOKEN="${HTTP_NET_AUTHTOKEN:-$(_readaccountconf_mutable HTTP_NET_AUTHTOKEN)}"

  if [ -z "$HTTP_NET_AUTHTOKEN" ]; then
    HTTP_NET_AUTHTOKEN=""
    _err "You don't specify http.net API token yet."
    _err "Please create you token and try again."
    return 1
  fi

  #save the api key and email to the account conf file.
  _saveaccountconf_mutable HTTP_NET_AUTHTOKEN "$HTTP_NET_AUTHTOKEN"

  _get_root "$fulldomain"

  payload=$(printf '{
    "authToken": "%s",
    "zoneConfig": {
        "name": "%s"
    },
    "recordsToAdd": [
        {
            "name": "%s",
            "type": "TXT",
            "content": "%s",
            "ttl": 300
        }
    ]
}' "$HTTP_NET_AUTHTOKEN" "$_domain" "$fulldomain" "$txtvalue")

  _post "$payload" "${HTTP_NET_API}/zoneUpdate" "" "POST" "text/json"

}

dns_http_net_rm() {

  fulldomain=$1
  txtvalue=$2

  _get_root "$fulldomain"

  payload=$(printf '{
    "authToken": "%s",
    "zoneConfig": {
        "name": "%s"
    },
    "recordsToDelete": [
        {
            "name": "%s",
            "type": "TXT",
            "content": "\\"%s\\""
        }
    ]
}' "$HTTP_NET_AUTHTOKEN" "$_domain" "$fulldomain" "$txtvalue")

  _post "$payload" "${HTTP_NET_API}/zoneUpdate" "" "POST" "text/json"
}

#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com

_get_root() {
  domain=$1
  i=2
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi
    _debug "Detecting if $h is the dns zone"

    if _check_http_net_zone "$h"; then
      _domain="$h"
      return 0
    fi
    i=$(_math "$i" + 1)
  done
  return 1
}

_check_http_net_zone() {
  domain2check=$1

  _debug "Checking for zoneConfig of $domain2check"

  payload=$(printf '{
  "authToken": "%s",
  "filter": {
    "field": "ZoneNameUnicode",  
    "value": "%s"
  }
}' "$HTTP_NET_AUTHTOKEN" "$domain2check")

  response="$(_post "$payload" "${HTTP_NET_API}/zoneConfigsFind" "" "POST" "text/json")"

  if _contains "$response" '"totalEntries": 1,' >/dev/null; then
    _debug "Detect $domain2check as a valid DNS zone"
    return 0
  fi
  return 1
}
