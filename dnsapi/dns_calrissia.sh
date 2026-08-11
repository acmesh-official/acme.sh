#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_calrissia_info='Calrissia.be DNS API
Site: calrissia.be
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_calrissia
Options:
 CALRISSIA_TOKEN Personal access token
Issues: github.com/acmesh-official/acme.sh/issues/6809
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

  return 0
}

dns_calrissia_rm() {
  fulldomain="$1"
  txtvalue="$2"

  _calrissia_load_token || return 1

  if ! _calrissia_get_root "$fulldomain"; then
    _err "Unable to find domain in Calrissia account for: $fulldomain"
    return 1
  fi

  _debug "domain='$_domain' id='$_domain_id' sub='$_sub_domain'"

  # Look the record up from the API instead of relying on local state.
  # The record list is embedded in the domain object.
  _response="$(_calrissia_request GET "/domain/$_domain_id")"
  _debug2 "Response: $_response"

  # Split the record objects onto separate lines, then match on both the
  # subdomain name and the TXT value to find the record id to delete.
  _record_id="$(printf "%s" "$_response" |
    tr '{}' '\n' |
    grep "\"name\" *: *\"$_sub_domain\"" |
    grep "\"content\" *: *\"$txtvalue\"" |
    _egrep_o '"id" *: *[0-9]+' |
    _head_n 1 |
    _egrep_o '[0-9]+')"

  if [ -z "$_record_id" ]; then
    _info "No matching TXT record found for $fulldomain; nothing to remove"
    return 0
  fi

  _info "Removing TXT record id=$_record_id from domain id=$_domain_id"
  if ! _response="$(_calrissia_request DELETE "/domain/$_domain_id/record/$_record_id")" || _contains "$_response" '"error"'; then
    _err "Failed to remove TXT record: $_response"
    return 1
  fi
  return 0
}

####################
# Private helpers  #
####################

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
      if [ "$i" = "1" ]; then
        # The FQDN itself is the zone apex, e.g. a challenge-alias domain.
        _sub_domain=""
      else
        _sub_domain="$(printf "%s" "$_fqdn" | cut -d . -f "1-$((i - 1))")"
      fi
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
