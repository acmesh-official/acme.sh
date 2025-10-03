#!/usr/bin/env sh

# LA_Id="123"
# LA_Sk="456"
# shellcheck disable=SC2034
dns_la_info='dns.la
Site: dns.la
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_la
Options:
 LA_Id APIID
 LA_Sk APISecret
 LA_Token 用冒号连接 APIID APISecret 再base64生成
Issues: github.com/acmesh-official/acme.sh/issues/4257
'
LA_Api="https://api.dns.la/api"

########  Public functions #####################

#Usage: dns_la_add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_la_add() {
  fulldomain=$1
  txtvalue=$2

  LA_Id="${LA_Id:-$(_readaccountconf_mutable LA_Id)}"
  LA_Sk="${LA_Sk:-$(_readaccountconf_mutable LA_Sk)}"
  _log "LA_Id=$LA_Id"
  _log "LA_Sk=$LA_Sk"

  if [ -z "$LA_Id" ] || [ -z "$LA_Sk" ]; then
    LA_Id=""
    LA_Sk=""
    _err "You didn't specify a dnsla api id and key yet."
    return 1
  fi

  #save the api key and email to the account conf file.
  _saveaccountconf_mutable LA_Id "$LA_Id"
  _saveaccountconf_mutable LA_Sk "$LA_Sk"

  # generate dnsla token
  _la_token

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _info "Adding record"

  # record type is enum in new api, 16 for TXT
  if _la_post "{\"domainId\":\"$_domain_id\",\"type\":16,\"host\":\"$_sub_domain\",\"data\":\"$txtvalue\",\"ttl\":600}" "record"; then
    if _contains "$response" '"id":'; then
      _info "Added, OK"
      return 0
    elif _contains "$response" '"msg":"与已有记录冲突"'; then
      _info "Already exists, OK"
      return 0
    else
      _err "Add txt record error."
      return 1
    fi
  fi
  _err "Add txt record failed."
  return 1

}

#fulldomain txtvalue
dns_la_rm() {
  fulldomain=$1
  txtvalue=$2

  LA_Id="${LA_Id:-$(_readaccountconf_mutable LA_Id)}"
  LA_Sk="${LA_Sk:-$(_readaccountconf_mutable LA_Sk)}"

  _la_token

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting txt records"
  # record type is enum in new api, 16 for TXT
  if ! _la_get "recordList?pageIndex=1&pageSize=10&domainId=$_domain_id&host=$_sub_domain&type=16&data=$txtvalue"; then
    _err "Error"
    return 1
  fi

  if ! _contains "$response" '"id":'; then
    _info "Don't need to remove."
    return 0
  fi

  record_id=$(printf "%s" "$response" | grep '"id":' | _head_n 1 | sed 's/.*"id": *"\([^"]*\)".*/\1/')
  _debug "record_id" "$record_id"
  if [ -z "$record_id" ]; then
    _err "Can not get record id to remove."
    return 1
  fi
  # remove record in new api is RESTful
  if ! _la_post "" "record?id=$record_id" "DELETE"; then
    _err "Delete record error."
    return 1
  fi
  _contains "$response" '"code":200'

}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
# _domain_id=sdjkglgdfewsdfg
_get_root() {
  domain=$1
  i=1
  p=1

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    if ! _la_get "domain?domain=$h"; then
      return 1
    fi

    if _contains "$response" '"domain":'; then
      _domain_id=$(echo "$response" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
      _log "_domain_id" "$_domain_id"
      if [ "$_domain_id" ]; then
        _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-"$p")
        _domain="$h"
        return 0
      fi
      return 1
    fi
    p="$i"
    i=$(_math "$i" + 1)
  done
  return 1
}

#Usage:  URI
_la_rest() {
  url="$LA_Api/$1"
  _debug "$url"

  if ! response="$(_get "$url" "Authorization: Basic $LA_Token" | tr -d ' ' | tr "}" ",")"; then
    _err "Error: $url"
    return 1
  fi

  _debug2 response "$response"
  return 0
}

_la_get() {
  url="$LA_Api/$1"
  _debug "$url"

  export _H1="Authorization: Basic $LA_Token"

  if ! response="$(_get "$url" | tr -d ' ' | tr "}" ",")"; then
    _err "Error: $url"
    return 1
  fi

  _debug2 response "$response"
  return 0
}

# Usage:  _la_post body url [POST|PUT|DELETE]
_la_post() {
  body=$1
  url="$LA_Api/$2"
  http_method=$3
  _debug "$body"
  _debug "$url"

  export _H1="Authorization: Basic $LA_Token"

  if ! response="$(_post "$body" "$url" "" "$http_method")"; then
    _err "Error: $url"
    return 1
  fi

  _debug2 response "$response"
  return 0
}

_la_token() {
  LA_Token=$(printf "%s:%s" "$LA_Id" "$LA_Sk" | _base64)
  _debug "$LA_Token"

  return 0
}
