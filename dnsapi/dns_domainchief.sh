#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_domainchief_info='Domain Chief
Site: domain.chief.app
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_domainchief
Options:
 DOMAINCHIEF_API_TOKEN API token with the domainchief:acme:write scope
OptionsAlt:
 DOMAINCHIEF_API_URL Override the API base URL. Default "https://domain.chief.app/api/v1".
Issues: github.com/acmesh-official/acme.sh/issues
'

DOMAINCHIEF_API_URL_DEFAULT="https://domain.chief.app/api/v1"
DOMAINCHIEF_MAX_ATTEMPTS=3

########  Public functions #####################

#Usage: dns_domainchief_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_domainchief_add() {
  fulldomain="$(_idn "$1")"
  txtvalue="$2"

  _info "Using Domain Chief"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  if ! _domainchief_init; then
    return 1
  fi

  # The API resolves the domain from the challenge name and keeps other values on the same name,
  # so no zone lookup is needed and wildcard and apex challenges can be published side by side.
  if ! _domainchief_api POST "/acme/challenges" "{\"name\":\"$fulldomain\",\"value\":\"$txtvalue\"}"; then
    return 1
  fi

  case "$_domainchief_http_code" in
  200 | 201)
    _info "Added TXT record for $fulldomain"
    return 0
    ;;
  esac

  _domainchief_error "Failed to add TXT record for $fulldomain"
  return 1
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_domainchief_rm() {
  fulldomain="$(_idn "$1")"
  txtvalue="$2"

  _info "Using Domain Chief"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  if ! _domainchief_init; then
    return 1
  fi

  if ! _domainchief_api DELETE "/acme/challenges?name=$(printf "%s" "$fulldomain" | _url_encode)&value=$(printf "%s" "$txtvalue" | _url_encode)"; then
    return 1
  fi

  case "$_domainchief_http_code" in
  204 | 404)
    _info "Removed TXT record for $fulldomain"
    return 0
    ;;
  esac

  _domainchief_error "Failed to remove TXT record for $fulldomain"
  return 1
}

####################  Private functions below ##################################

_domainchief_init() {
  DOMAINCHIEF_API_TOKEN="${DOMAINCHIEF_API_TOKEN:-$(_readaccountconf_mutable DOMAINCHIEF_API_TOKEN)}"
  DOMAINCHIEF_API_URL="${DOMAINCHIEF_API_URL:-$(_readaccountconf_mutable DOMAINCHIEF_API_URL)}"

  if [ -z "$DOMAINCHIEF_API_TOKEN" ]; then
    DOMAINCHIEF_API_TOKEN=""
    _err "You did not specify a Domain Chief API token."
    _err "Create a token with the domainchief:acme:write scope at https://account.chief.app/team/select/token/create?scopes=domainchief:acme:write and export it as DOMAINCHIEF_API_TOKEN."
    return 1
  fi

  _saveaccountconf_mutable DOMAINCHIEF_API_TOKEN "$DOMAINCHIEF_API_TOKEN"

  # Setting the default URL again clears a previously saved custom URL.
  if [ -z "$DOMAINCHIEF_API_URL" ] || [ "$DOMAINCHIEF_API_URL" = "$DOMAINCHIEF_API_URL_DEFAULT" ]; then
    DOMAINCHIEF_API_URL="$DOMAINCHIEF_API_URL_DEFAULT"
    _clearaccountconf_mutable DOMAINCHIEF_API_URL
  else
    _saveaccountconf_mutable DOMAINCHIEF_API_URL "$DOMAINCHIEF_API_URL"
  fi

  return 0
}

# Usage: _domainchief_api METHOD PATH [BODY]
# Sets _domainchief_http_code and response, retries while another DNS write for the domain is running.
_domainchief_api() {
  method="$1"
  path="$2"
  data="$3"
  attempt=1

  export _H1="Authorization: Bearer $DOMAINCHIEF_API_TOKEN"
  export _H2="Accept: application/json"
  export _H3=""
  export _H4=""
  export _H5=""

  while true; do
    response="$(_post "$data" "$DOMAINCHIEF_API_URL$path" "" "$method" "application/json")"
    ret="$?"

    _domainchief_http_code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d '\r\n')"
    _debug2 response "$response"
    _debug _domainchief_http_code "$_domainchief_http_code"

    if [ "$ret" != "0" ]; then
      _err "Domain Chief API request failed."
      return 1
    fi

    if [ "$attempt" -ge "$DOMAINCHIEF_MAX_ATTEMPTS" ] || ! _domainchief_retryable; then
      return 0
    fi

    _info "Domain Chief is busy with another DNS change for this domain, retrying."
    _sleep "$((attempt * 2))"
    attempt="$((attempt + 1))"
  done
}

_domainchief_retryable() {
  case "$_domainchief_http_code" in
  429 | 5*)
    return 0
    ;;
  409)
    _contains "$response" '"dns.zone_busy"' || _contains "$response" '"dns.zone_changed"'
    return
    ;;
  esac

  return 1
}

_domainchief_error() {
  message="$(printf "%s" "$response" | _egrep_o '"message": *"[^"]*"' | cut -d '"' -f 4)"

  if [ "$_domainchief_http_code" = "401" ] || [ "$_domainchief_http_code" = "403" ]; then
    _err "$1: the API token is invalid or does not have the domainchief:acme:write scope (HTTP $_domainchief_http_code)."
  elif [ -n "$message" ]; then
    _err "$1: $message (HTTP $_domainchief_http_code)"
  else
    _err "$1 (HTTP $_domainchief_http_code)"
  fi
}
