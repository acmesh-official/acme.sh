#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_edgecenter_info='EdgeCenter.ru
Site: EdgeCenter.ru
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_edgecenter
Options:
 EDGECENTER_API_KEY API Key
Issues: github.com/acmesh-official/acme.sh/issues/6313
Author: Konstantin Ruchev <konstantin.ruchev@edgecenter.ru>
'

EDGECENTER_API="https://api.edgecenter.ru"
DOMAIN_TYPE=
DOMAIN_MASTER=

########  Public functions #####################

#Usage: dns_edgecenter_add   _acme-challenge.www.domain.com   "TXT_RECORD_VALUE"
dns_edgecenter_add() {
  fulldomain="$1"
  txtvalue="$2"

  _info "Using EdgeCenter DNS API"

  if ! _dns_edgecenter_init_check; then
    return 1
  fi

  _debug "Detecting root zone for $fulldomain"
  if ! _get_root "$fulldomain"; then
    return 1
  fi

  subdomain="${fulldomain%."$_zone"}"
  subdomain=${subdomain%.}

  _debug "Zone: $_zone"
  _debug "Subdomain: $subdomain"
  _debug "TXT value: $txtvalue"

  payload='{"resource_records": [ { "content": ["'"$txtvalue"'"] } ], "ttl": 60 }'
  _dns_edgecenter_http_api_call "post" "dns/v2/zones/$_zone/$subdomain.$_zone/txt" "$payload"

  if _contains "$response" '"error":"rrset is already exists"'; then
    _debug "RRSet exists, merging values"
    _dns_edgecenter_http_api_call "get" "dns/v2/zones/$_zone/$subdomain.$_zone/txt"
    current="$response"
    newlist=""
    for v in $(echo "$current" | sed -n 's/.*"content":\["\([^"]*\)"\].*/\1/p'); do
      newlist="$newlist {\"content\":[\"$v\"]},"
    done
    newlist="$newlist{\"content\":[\"$txtvalue\"]}"
    putdata="{\"resource_records\":[${newlist}]}
"
    _dns_edgecenter_http_api_call "put" "dns/v2/zones/$_zone/$subdomain.$_zone/txt" "$putdata"
    _info "Updated existing RRSet with new TXT value."
    return 0
  fi

  if _contains "$response" '"exception":'; then
    _err "Record cannot be added."
    return 1
  fi

  _info "TXT record added successfully."
  return 0
}

#Usage: dns_edgecenter_rm   _acme-challenge.www.domain.com   "TXT_RECORD_VALUE"
dns_edgecenter_rm() {
  fulldomain="$1"
  txtvalue="$2"

  _info "Removing TXT record for $fulldomain"

  if ! _dns_edgecenter_init_check; then
    return 1
  fi

  if ! _get_root "$fulldomain"; then
    return 1
  fi

  subdomain="${fulldomain%."$_zone"}"
  subdomain=${subdomain%.}

  _dns_edgecenter_http_api_call "delete" "dns/v2/zones/$_zone/$subdomain.$_zone/txt"

  if [ -z "$response" ]; then
    _info "TXT record deleted successfully."
  else
    _info "TXT record may not have been deleted: $response"
  fi
  return 0
}

####################  Private functions below ##################################

_dns_edgecenter_init_check() {
  EDGECENTER_API_KEY="${EDGECENTER_API_KEY:-$(_readaccountconf_mutable EDGECENTER_API_KEY)}"
  if [ -z "$EDGECENTER_API_KEY" ]; then
    _err "EDGECENTER_API_KEY was not exported."
    return 1
  fi

  _saveaccountconf_mutable EDGECENTER_API_KEY "$EDGECENTER_API_KEY"
  export _H1="Authorization: APIKey $EDGECENTER_API_KEY"

  _dns_edgecenter_http_api_call "get" "dns/v2/clients/me/features"
  if ! _contains "$response" '"id":'; then
    _err "Invalid API key."
    return 1
  fi
  return 0
}

_get_root() {
  domain="$1"
  i=1
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-)
    if [ -z "$h" ]; then
      return 1
    fi
    _dns_edgecenter_http_api_call "get" "dns/v2/zones/$h"
    if ! _contains "$response" 'zone is not found'; then
      _zone="$h"
      return 0
    fi
    i=$((i + 1))
  done
  return 1
}

_dns_edgecenter_http_api_call() {
  mtd="$1"
  endpoint="$2"
  data="$3"

  export _H1="Authorization: APIKey $EDGECENTER_API_KEY"

  case "$mtd" in
  get)
    response="$(_get "$EDGECENTER_API/$endpoint")"
    ;;
  post)
    response="$(_post "$data" "$EDGECENTER_API/$endpoint")"
    ;;
  delete)
    response="$(_post "" "$EDGECENTER_API/$endpoint" "" "DELETE")"
    ;;
  put)
    response="$(_post "$data" "$EDGECENTER_API/$endpoint" "" "PUT")"
    ;;
  *)
    _err "Unknown HTTP method $mtd"
    return 1
    ;;
  esac

  _debug "HTTP $mtd response: $response"
  return 0
}
