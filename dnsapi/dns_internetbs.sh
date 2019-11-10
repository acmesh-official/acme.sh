#!/usr/bin/env sh

#This is the Internet.BS api wrapper for acme.sh
#
#Author: <alexey@nelexa.ru> Ne-Lexa
#Report Bugs here: https://github.com/Ne-Lexa/acme.sh

#INTERNETBS_API_KEY="sdfsdfsdfljlbjkljlkjsdfoiwje"
#INTERNETBS_API_PASSWORD="sdfsdfsdfljlbjkljlkjsdfoiwje"

INTERNETBS_API_URL="https://api.internet.bs"

########  Public functions #####################

#Usage: dns_myapi_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_internetbs_add() {
  fulldomain=$1
  txtvalue=$2

  INTERNETBS_API_KEY="${INTERNETBS_API_KEY:-$(_readaccountconf_mutable INTERNETBS_API_KEY)}"
  INTERNETBS_API_PASSWORD="${INTERNETBS_API_PASSWORD:-$(_readaccountconf_mutable INTERNETBS_API_PASSWORD)}"

  if [ -z "$INTERNETBS_API_KEY" ] || [ -z "$INTERNETBS_API_PASSWORD" ]; then
    INTERNETBS_API_KEY=""
    INTERNETBS_API_PASSWORD=""
    _err "You didn't specify the INTERNET.BS api key and password yet."
    _err "Please create you key and try again."
    return 1
  fi

  _saveaccountconf_mutable INTERNETBS_API_KEY "$INTERNETBS_API_KEY"
  _saveaccountconf_mutable INTERNETBS_API_PASSWORD "$INTERNETBS_API_PASSWORD"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  # https://testapi.internet.bs/Domain/DnsRecord/Add?ApiKey=testapi&Password=testpass&FullRecordName=w3.test-api-domain7.net&Type=CNAME&Value=www.internet.bs%&ResponseFormat=json
  if _internetbs_rest POST "Domain/DnsRecord/Add" "FullRecordName=${_sub_domain}.${_domain}&Type=TXT&Value=${txtvalue}&ResponseFormat=json"; then
    if ! _contains "$response" "\"status\":\"SUCCESS\""; then
      _err "ERROR add TXT record"
      _err "$response"
      return 1
    fi

    _info "txt record add success."
    return 0
  fi

  return 1
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_internetbs_rm() {
  fulldomain=$1
  txtvalue=$2

  INTERNETBS_API_KEY="${INTERNETBS_API_KEY:-$(_readaccountconf_mutable INTERNETBS_API_KEY)}"
  INTERNETBS_API_PASSWORD="${INTERNETBS_API_PASSWORD:-$(_readaccountconf_mutable INTERNETBS_API_PASSWORD)}"

  if [ -z "$INTERNETBS_API_KEY" ] || [ -z "$INTERNETBS_API_PASSWORD" ]; then
    INTERNETBS_API_KEY=""
    INTERNETBS_API_PASSWORD=""
    _err "You didn't specify the INTERNET.BS api key and password yet."
    _err "Please create you key and try again."
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting txt records"
  # https://testapi.internet.bs/Domain/DnsRecord/List?ApiKey=testapi&Password=testpass&Domain=test-api-domain7.net&FilterType=CNAME&ResponseFormat=json
  _internetbs_rest POST "Domain/DnsRecord/List" "Domain=$_domain&FilterType=TXT&ResponseFormat=json"

  if ! _contains "$response" "\"status\":\"SUCCESS\""; then
    _err "ERROR list dns records"
    _err "$response"
    return 1
  fi

  if _contains "$response" "\name\":\"${_sub_domain}.${_domain}\""; then
    _info "txt record find."

    # https://testapi.internet.bs/Domain/DnsRecord/Remove?ApiKey=testapi&Password=testpass&FullRecordName=www.test-api-domain7.net&Type=cname&ResponseFormat=json
    _internetbs_rest POST "Domain/DnsRecord/Remove" "FullRecordName=${_sub_domain}.${_domain}&Type=TXT&ResponseFormat=json"

    if ! _contains "$response" "\"status\":\"SUCCESS\""; then
      _err "ERROR remove dns record"
      _err "$response"
      return 1
    fi

    _info "txt record deleted success."
    return 0
  fi

  return 1
}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
# _domain_id=12345
_get_root() {
  domain=$1
  i=2
  p=1

  # https://testapi.internet.bs/Domain/List?ApiKey=testapi&Password=testpass&CompactList=yes&ResponseFormat=json
  if _internetbs_rest POST "Domain/List" "CompactList=yes&ResponseFormat=json"; then

    if ! _contains "$response" "\"status\":\"SUCCESS\""; then
      _err "ERROR fetch domain list"
      _err "$response"
      return 1
    fi

    while true; do
      h=$(printf "%s" "$domain" | cut -d . -f ${i}-100)
      _debug h "$h"
      if [ -z "$h" ]; then
        #not valid
        return 1
      fi

      if _contains "$response" "\"$h\""; then
        _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-${p})
        _domain=${h}
        return 0
      fi

      p=${i}
      i=$(_math "$i" + 1)
    done
  fi
  return 1
}

#Usage: method  URI  data
_internetbs_rest() {
  m="$1"
  ep="$2"
  data="$3"
  url="${INTERNETBS_API_URL}/${ep}"

  _debug url "$url"

  apiKey="$(printf "%s" "${INTERNETBS_API_KEY}" | _url_encode)"
  password="$(printf "%s" "${INTERNETBS_API_PASSWORD}" | _url_encode)"

  if [ "$m" = "GET" ]; then
    response="$(_get "${url}?ApiKey=${apiKey}&Password=${password}&${data}" | tr -d '\r')"
  else
    _debug2 data "$data"
    response="$(_post "$data" "${url}?ApiKey=${apiKey}&Password=${password}" | tr -d '\r')"
  fi

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi

  _debug2 response "$response"
  return 0
}
