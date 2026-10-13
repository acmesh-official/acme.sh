#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_pblin_info='publicinternet.com
Domains: public-internet.co.uk pblin.net
Site: www.publicinternet.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_pblin
Options:
 PBLIN_API_KEY API Key. Create an API key in the Public Internet customer portal at https://portal.publicinternet.com. A key is scoped to one domain, so each certificate needs the key for its own domain
Issues: github.com/acmesh-official/acme.sh/issues/7314
Author: Public Internet <https://github.com/publicinternet>
'

PBLIN_Api="https://api.pblin.net/dns"

#Usage: dns_pblin_add _acme-challenge.www.domain.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_pblin_add() {
  fulldomain=$(_idn "$1")
  txtvalue=$2

  if ! _pblin_init; then
    return 1
  fi

  if ! _get_root "$fulldomain"; then
    return 1
  fi

  #an API key is scoped to one zone, so it is kept per certificate, and only once a zone lookup has accepted it
  _savedomainconf SAVED_PBLIN_API_KEY "$PBLIN_API_KEY"
  #the out-of-tree dns_pblin.sh saved the key unprefixed, which a renewal would load over a newly exported key
  _cleardomainconf PBLIN_API_KEY

  _info "Adding TXT record for $fulldomain"
  if ! _pblin_rest POST "domains/$_domain/records" "{\"type\":\"TXT\",\"name\":\"$fulldomain\",\"content\":\"$txtvalue\",\"ttl\":600}"; then
    _err "Failed to add TXT record: $_message"
    return 1
  fi

  _info "TXT record added"
  return 0
}

#Usage: dns_pblin_rm _acme-challenge.www.domain.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_pblin_rm() {
  fulldomain=$(_idn "$1")
  txtvalue=$2

  if ! _pblin_init; then
    return 1
  fi

  if ! _get_root "$fulldomain"; then
    return 1
  fi

  _info "Removing TXT record for $fulldomain"
  if ! _pblin_rest GET "domains/$_domain/records?type=TXT&name=$fulldomain"; then
    _err "Failed to list TXT records: $_message"
    return 1
  fi

  #the API has no content filter and accepts duplicates, so match the value here and remove every copy
  _record_ids="$(echo "$response" | tr '{' '\n' | grep "\"content\":\"$txtvalue\"" | _egrep_o '"id" *: *[0-9]*' | cut -d : -f 2 | tr -d ' ')"
  _debug _record_ids "$_record_ids"

  if [ -z "$_record_ids" ]; then
    _info "TXT record already removed"
    return 0
  fi

  for _record_id in $_record_ids; do
    if ! _pblin_rest DELETE "domains/$_domain/records/$_record_id" && [ "$_code" != "404" ]; then
      _err "Failed to remove TXT record $_record_id: $_message"
      return 1
    fi
  done

  _info "TXT record removed"
  return 0
}

_pblin_init() {
  #the SAVED_ prefix keeps a reloaded certificate conf from overriding a newly exported key
  PBLIN_API_KEY="${PBLIN_API_KEY:-$(_readdomainconf SAVED_PBLIN_API_KEY)}"
  #only renewals load the out-of-tree plugin's unprefixed key, so read it here for --issue too
  PBLIN_API_KEY="${PBLIN_API_KEY:-$(_readdomainconf PBLIN_API_KEY)}"

  if [ -z "$PBLIN_API_KEY" ]; then
    _err "PBLIN_API_KEY is not set. Create an API key in the Public Internet customer portal at https://portal.publicinternet.com, then:"
    _err "export PBLIN_API_KEY=\"your-api-key\""
    return 1
  fi

  return 0
}

_get_root() {
  domain=$1
  i=1

  while true; do
    #-s: plain cut returns a dotless name (e.g. from --domain-alias) for every i, so the loop would keep querying it
    h=$(printf "%s" "$domain" | cut -s -d . -f "$i"-100)

    if [ -z "$h" ]; then
      _err "No zone for $domain found in this Public Internet account"
      return 1
    fi

    if _pblin_rest GET "domains/$h"; then
      _domain=$h
      return 0
    fi

    case "$_code" in
    404) ;;
    401 | 403)
      _err "The API key was rejected ($_message), check PBLIN_API_KEY"
      return 1
      ;;
    *)
      _err "Failed to look up zone $h: $_message"
      return 1
      ;;
    esac

    i=$(_math "$i" + 1)
  done
}

_pblin_rest() {
  m=$1
  ep=$2
  data=$3

  export _H1="Authorization: Bearer $PBLIN_API_KEY"
  export _H2="Content-Type: application/json"

  if [ "$m" = "GET" ]; then
    response="$(_get "$PBLIN_Api/$ep")"
  else
    response="$(_post "$data" "$PBLIN_Api/$ep" "" "$m")"
  fi

  if [ "$?" != "0" ]; then
    _code=""
    _message="connection failed"
    return 1
  fi

  #printf, not echo: dash's builtin echo interprets backslash escapes in record content
  response="$(printf "%s\n" "$response" | _normalizeJson)"
  _code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\r\n")"
  _debug2 _code "$_code"
  _debug2 response "$response"

  case "$_code" in
  2*) return 0 ;;
  esac

  _message="$(echo "$response" | _egrep_o '"message":"[^"]*"' | _head_n 1 | cut -d '"' -f 4)"
  _message="HTTP ${_code:-request failed}${_message:+: $_message}"
  return 1
}
