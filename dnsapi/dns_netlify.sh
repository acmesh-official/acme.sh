#!/usr/bin/env sh

#NETLIFY_ACCESS_TOKEN="xxxx"

NETLIFY_HOST="api.netlify.com/api/v1/"
NETLIFY_URL="https://$NETLIFY_HOST"

########  Public functions #####################

#Usage: dns_myapi_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_netlify_add() {
  fulldomain=$1
  txtvalue=$2

  NETLIFY_ACCESS_TOKEN="${NETLIFY_ACCESS_TOKEN:-$(_readaccountconf_mutable NETLIFY_ACCESS_TOKEN)}"

  if [ -z "$NETLIFY_ACCESS_TOKEN" ]; then
    NETLIFY_ACCESS_TOKEN=""
    _err "Please specify your Netlify Access Token and try again."
    return 1
  fi

  _info "Using Netlify"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  _saveaccountconf_mutable NETLIFY_ACCESS_TOKEN "$NETLIFY_ACCESS_TOKEN"

  if ! _get_root "$fulldomain" "$accesstoken"; then
    _err "invalid domain"
    return 1
  fi

  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  dnsRecordURI="dns_zones/$_domain_id/dns_records"

  body="{\"type\":\"TXT\", \"hostname\":\"$_sub_domain\", \"value\":\"$txtvalue\", \"ttl\":\"10\"}"

  _netlify_rest POST "$dnsRecordURI" "$body" "$NETLIFY_ACCESS_TOKEN"
  _code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\\r\\n")"
  if [ "$_code" = "200" ] || [ "$_code" = '201' ]; then
    _info "validation value added"
    return 0
  else
    _err "error adding validation value ($_code)"
    return 1
  fi

  _err "Not fully implemented!"
  return 1
}

#Usage: dns_myapi_rm   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
#Remove the txt record after validation.
dns_netlify_rm() {
  _info "Using Netlify"
  txtdomain="$1"
  txt="$2"
  _debug txtdomain "$txtdomain"
  _debug txt "$txt"

  _saveaccountconf_mutable NETLIFY_ACCESS_TOKEN "$NETLIFY_ACCESS_TOKEN"

  if ! _get_root "$txtdomain" "$accesstoken"; then
    _err "invalid domain"
    return 1
  fi

  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  dnsRecordURI="dns_zones/$_domain_id/dns_records"

  _netlify_rest GET "$dnsRecordURI" "" "$NETLIFY_ACCESS_TOKEN"

  _record_id=$(echo "$response" | _egrep_o "\"type\":\"TXT\",[^\}]*\"value\":\"$txt\"" | head -n 1 | _egrep_o "\"id\":\"[^\"\}]*\"" | cut -d : -f 2 | tr -d \")
  _debug _record_id "$_record_id"
  if [ "$_record_id" ]; then
    _netlify_rest DELETE "$dnsRecordURI/$_record_id" "" "$NETLIFY_ACCESS_TOKEN"
    _code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\\r\\n")"
    if [ "$_code" = "200" ] || [ "$_code" = '204' ]; then
      _info "validation value removed"
      return 0
    else
      _err "error removing validation value ($_code)"
      return 1
    fi
    return 0
  fi
  return 1
}

####################  Private functions below ##################################

_get_root() {
  domain=$1
  accesstoken=$2
  i=1
  p=1

  _netlify_rest GET "dns_zones" "" "$accesstoken"

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug2 "Checking domain: $h"
    if [ -z "$h" ]; then
      #not valid
      _err "Invalid domain"
      return 1
    fi

    if _contains "$response" "\"name\":\"$h\"" >/dev/null; then
      _domain_id=$(echo "$response" | _egrep_o "\"[^\"]*\",\"name\":\"$h" | cut -d , -f 1 | tr -d \")
      if [ "$_domain_id" ]; then
        if [ "$i" = 1 ]; then
          #create the record at the domain apex (@) if only the domain name was provided as --domain-alias
          _sub_domain="@"
        else
          _sub_domain=$(echo "$domain" | cut -d . -f 1-$p)
        fi
        _domain=$h
        return 0
      fi
      return 1
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

_netlify_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"

  token_trimmed=$(echo "$NETLIFY_ACCESS_TOKEN" | tr -d '"')

  export _H1="Content-Type: application/json"
  export _H2="Authorization: Bearer $token_trimmed"

  : >"$HTTP_HEADER"

  if [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$NETLIFY_URL$ep" "" "$m")"
  else
    response="$(_get "$NETLIFY_URL$ep")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
