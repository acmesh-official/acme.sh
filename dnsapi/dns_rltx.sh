#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_rltx_info='Realtox Media Cloudpanel DNS API
Site: realtoxmedia.de
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_rltx
Options:
 RLTX_Key API Key
 RLTX_OrganizationID Organization ID
'

########  Public functions #####################

#Usage: dns_rltx_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_rltx_add() {
  fulldomain=$1
  txtvalue=$2

  _info "Using Realtox Media Cloudpanel DNS API"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  if ! _rltx_init; then
    return 1
  fi

  if ! _get_root "$fulldomain"; then
    _err "Could not find matching DNS zone for $fulldomain"
    return 1
  fi

  _debug _domain_id "$_domain_id"
  _debug _domain "$_domain"
  _debug _sub_domain "$_sub_domain"

  data="{\"name\":\"$_sub_domain\",\"value\":\"$txtvalue\",\"ttl\":120}"
  if ! _rltx_rest POST "domains/$_domain_id/dns/acme-txt" "$data"; then
    _err "Add TXT record request failed"
    return 1
  fi
  if _contains "$response" '"status":"added"'; then
    _info "Added TXT record, OK"
    return 0
  fi
  _err "Add TXT record failed: $response"
  return 1
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_rltx_rm() {
  fulldomain=$1
  txtvalue=$2

  _info "Using Realtox Media Cloudpanel DNS API"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  if ! _rltx_init; then
    return 1
  fi

  if ! _get_root "$fulldomain"; then
    _err "Could not find matching DNS zone for $fulldomain"
    return 1
  fi

  _debug _domain_id "$_domain_id"
  _debug _domain "$_domain"
  _debug _sub_domain "$_sub_domain"

  data="{\"name\":\"$_sub_domain\",\"value\":\"$txtvalue\",\"ttl\":120}"
  if ! _rltx_rest DELETE "domains/$_domain_id/dns/acme-txt" "$data"; then
    _err "Remove TXT record request failed"
    return 1
  fi
  if _contains "$response" '"status":"removed"'; then
    _info "Removed TXT record, OK"
    return 0
  fi
  _err "Remove TXT record failed: $response"
  return 1
}

####################  Private functions below ##################################

_rltx_init() {
  RLTX_Key="${RLTX_Key:-$(_readaccountconf_mutable RLTX_Key)}"
  RLTX_OrganizationID="${RLTX_OrganizationID:-$(_readaccountconf_mutable RLTX_OrganizationID)}"

  if [ -z "$RLTX_Key" ] || [ -z "$RLTX_OrganizationID" ]; then
    RLTX_Key=""
    RLTX_OrganizationID=""
    _err "Please specify RLTX_Key and RLTX_OrganizationID."
    _err "You can export them and retry: export RLTX_Key=... RLTX_OrganizationID=..."
    return 1
  fi

  _saveaccountconf_mutable RLTX_Key "$RLTX_Key"
  _saveaccountconf_mutable RLTX_OrganizationID "$RLTX_OrganizationID"
}

_get_root() {
  domain=$1
  fqdn_encoded="$(printf "%s" "$domain" | _url_encode)"
  if ! _rltx_rest GET "domains/dns/acme-zone?fqdn=$fqdn_encoded"; then
    return 1
  fi
  if ! _contains "$response" '"domain_id":"'; then
    return 1
  fi

  _domain_id="$(printf "%s" "$response" | _egrep_o '"domain_id":"[^"]*"' | cut -d : -f 2 | tr -d '"' | _head_n 1)"
  _domain="$(printf "%s" "$response" | _egrep_o '"zone":"[^"]*"' | cut -d : -f 2 | tr -d '"' | _head_n 1)"
  _sub_domain="$(printf "%s" "$response" | _egrep_o '"record_name":"[^"]*"' | cut -d : -f 2 | tr -d '"' | _head_n 1)"

  if [ -z "$_domain_id" ] || [ -z "$_domain" ] || [ -z "$_sub_domain" ]; then
    return 1
  fi
  return 0
}

_rltx_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"

  export _H1="X-API-Key: $RLTX_Key"
  export _H2="X-Organization-ID: $RLTX_OrganizationID"
  export _H3="Content-Type: application/json"

  if [ "$m" = "GET" ]; then
    response="$(_get "https://api.ccp.realtoxmedia.de/api/$ep")"
  else
    _debug2 data "$data"
    response="$(_post "$data" "https://api.ccp.realtoxmedia.de/api/$ep" "" "$m")"
  fi

  if [ "$?" != "0" ]; then
    _err "Realtox Media Cloudpanel API request failed: $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
