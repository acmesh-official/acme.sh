#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_calrissia_info='Calrissia.be DNS API
Site: calrissia.be
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_calrissia
Options:
 CALRISSIA_TOKEN Personal access token
Issues: github.com/acmesh-official/acme.sh/pull/6802
Author: Ward Hus
'

CALRISSIA_API="https://my.calrissia.com/api"

dns_calrissia_add() {
  fulldomain="$1"
  txtvalue="$2"

  _calrissia_load_token || return 1

  if ! _calrissia_get_root "$fulldomain"; then
    _err "Unable to find domain in Calrissia account for: $fulldomain"
    return 1
  fi

  _debug "domain='$_domain' id='$_domain_id' sub='$_sub_domain'"
  _info "Adding TXT record for $fulldomain"

  _body="{\"name\":\"$_sub_domain\",\"type\":\"TXT\",\"content\":\"$txtvalue\",\"ttl\":120,\"prio\":0}"
  _response="$(_calrissia_request POST "/domain/$_domain_id/record" "$_body")"

  if ! _contains "$_response" '"id"'; then
    _err "Failed to create TXT record: $_response"
    return 1
  fi

  _record_id="$(printf "%s" "$_response" | _egrep_o '"id" *: *[0-9]+' | _egrep_o '[0-9]+')"
  _key="$(_calrissia_key "$fulldomain" "$txtvalue")"
  _savedomainconf "CALRISSIA_RECORD_ID_$_key" "$_record_id"
  _savedomainconf "CALRISSIA_DOMAIN_ID_$_key" "$_domain_id"

  return 0
}

dns_calrissia_rm() {
  fulldomain="$1"
  txtvalue="$2"

  _calrissia_load_token || return 1

  _key="$(_calrissia_key "$fulldomain" "$txtvalue")"
  _record_id="$(_readdomainconf "CALRISSIA_RECORD_ID_$_key")"
  _domain_id="$(_readdomainconf "CALRISSIA_DOMAIN_ID_$_key")"

  if [ -z "$_record_id" ] || [ -z "$_domain_id" ]; then
    _err "No saved record for $fulldomain; cannot remove"
    return 1
  fi

  _info "Removing TXT record id=$_record_id from domain id=$_domain_id"
  _calrissia_request DELETE "/domain/$_domain_id/record/$_record_id"

  _cleardomainconf "CALRISSIA_RECORD_ID_$_key"
  _cleardomainconf "CALRISSIA_DOMAIN_ID_$_key"
  return 0
}

####################
# Private helpers  #
####################

# Build a unique conf key from fulldomain and txtvalue.
_calrissia_key() {
  printf "%s_%s" "$1" "$2" | tr '.-' '__'
}

_calrissia_load_token() {
  CALRISSIA_TOKEN="${CALRISSIA_TOKEN:-$(_readaccountconf_mutable CALRISSIA_TOKEN)}"
  if [ -z "$CALRISSIA_TOKEN" ]; then
    _err "CALRISSIA_TOKEN is not set. Generate one at https://identity.calrissia.com under API Keys."
    return 1
  fi
  _saveaccountconf_mutable CALRISSIA_TOKEN "$CALRISSIA_TOKEN"
}

# Sets _domain, _domain_id, _sub_domain for a given FQDN.
_calrissia_get_root() {
  _fqdn="$1"

  i=1
  while true; do
    _candidate="$(printf "%s" "$_fqdn" | cut -d . -f "$i"-)"
    [ -z "$_candidate" ] && return 1

    _debug "Trying root domain: $_candidate"
    _response="$(_calrissia_request GET "/domain?full_domain_name=$_candidate")"
    _debug2 "Response: $_response"

    _domain_id="$(printf "%s" "$_response" |
      _egrep_o '"id" *: *[0-9]+' |
      _head_n 1 |
      _egrep_o '[0-9]+')"

    if [ -n "$_domain_id" ]; then
      _sub_domain="$(printf "%s" "$_fqdn" | cut -d . -f "1-$((i - 1))")"
      _domain="$_candidate"
      return 0
    fi

    i=$((i + 1))
  done
}

_calrissia_request() {
  _method="$1"
  _path="$2"
  _body="$3"
  export _H1="Authorization: Bearer $CALRISSIA_TOKEN"
  export _H2="Accept: application/json"
  if [ "$_method" = "GET" ]; then
    _get "$CALRISSIA_API$_path"
  else
    _post "$_body" "$CALRISSIA_API$_path" "" "$_method" "application/json"
  fi
}
