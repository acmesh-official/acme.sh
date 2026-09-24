#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_feno_info='FENO
Site: feno.no
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_feno
Options:
 FENO_API_KEY API key with the acme:write scope (feno_live_...)
 FENO_API_BASE API base URL. Optional. Default: "https://api.feno.no".
Issues: github.com/acmesh-official/acme.sh/issues/7228
Author: Erik Nilsen <eriknilsen02@hotmail.com>
'

# FENO (feno.no) is a Norwegian .no registrar. API documentation:
# https://github.com/mrerikcodes/feno-api/blob/main/docs/README.md
# The API key only needs the acme:write scope: it covers the zone lookup and
# TXT records at _acme-challenge names.

FENO_API_BASE_DEFAULT="https://api.feno.no"

########  Public functions #####################

# Usage: dns_feno_add  _acme-challenge.www.kunde.no  "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_feno_add() {
  fulldomain=$1
  txtvalue=$2

  _info "Using FENO"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  if ! _feno_credentials; then
    return 1
  fi

  if ! _get_root "$fulldomain"; then
    _err "Could not find a FENO domain covering $fulldomain."
    _err "The domain must be registered with FENO and use FENO nameservers (ns1/ns2.feno.no)."
    return 1
  fi
  _debug _domain "$_domain"
  _debug _sub_domain "$_sub_domain"

  _feno_json="{\"type\":\"TXT\",\"name\":\"$_sub_domain\",\"value\":\"$txtvalue\",\"ttl\":60}"
  if ! _feno_rest POST "v1/domains/$_domain/dns" "$_feno_json"; then
    return 1
  fi

  if ! _contains "$response" '"success":true'; then
    _err "FENO refused the TXT record: $response"
    return 1
  fi

  _info "TXT record added."
  return 0
}

# Usage: dns_feno_rm  _acme-challenge.www.kunde.no  "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_feno_rm() {
  fulldomain=$1
  txtvalue=$2

  _info "Using FENO"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  if ! _feno_credentials; then
    return 1
  fi

  if ! _get_root "$fulldomain"; then
    _err "Could not find a FENO domain covering $fulldomain."
    return 1
  fi
  _debug _domain "$_domain"
  _debug _sub_domain "$_sub_domain"

  # The API has no "delete by value" - the record id has to be looked up by listing the zone
  # and matching name + type + value. Matching the value too is what keeps a wildcard
  # certificate safe: kunde.no and *.kunde.no put TWO TXT records at the same name, and only
  # the one this call created may be removed.
  if ! _feno_rest GET "v1/domains/$_domain/dns"; then
    return 1
  fi

  # Same guard as the zone walk: an auth failure here returns no records, which would
  # otherwise be read as "the record is already gone" and reported as success.
  if _feno_code=$(_feno_auth_error); then
    _err "FENO rejected the API key while listing $_domain ($_feno_code)."
    return 1
  fi

  _record_id=$(_feno_find_record_id "$_sub_domain" "$txtvalue")
  if [ -z "$_record_id" ]; then
    # Already gone (an earlier cleanup, or a manual edit). Not an error: the desired state holds.
    _info "No matching TXT record found, nothing to remove."
    return 0
  fi
  _debug _record_id "$_record_id"

  if ! _feno_rest DELETE "v1/domains/$_domain/dns/$_record_id"; then
    return 1
  fi

  if ! _contains "$response" '"success":true'; then
    _err "FENO refused to delete the TXT record: $response"
    return 1
  fi

  _info "TXT record removed."
  return 0
}

####################  Private functions below ##################################

# Read FENO_API_KEY / FENO_API_BASE from the environment or the saved account conf, and
# persist them, so an unattended renewal from cron works with nothing exported.
_feno_credentials() {
  FENO_API_KEY="${FENO_API_KEY:-$(_readaccountconf_mutable FENO_API_KEY)}"
  FENO_API_BASE="${FENO_API_BASE:-$(_readaccountconf_mutable FENO_API_BASE)}"

  if [ -z "$FENO_API_KEY" ]; then
    FENO_API_KEY=""
    _err "You have not set FENO_API_KEY yet."
    _err "Create a public API key with the acme:write scope in the FENO dashboard, then:"
    _err '  export FENO_API_KEY="feno_live_xxxxxxxx"'
    return 1
  fi
  _secure_debug FENO_API_KEY "$FENO_API_KEY"

  if [ -z "$FENO_API_BASE" ]; then
    FENO_API_BASE="$FENO_API_BASE_DEFAULT"
  fi
  # A trailing slash would produce "//v1/..." paths.
  FENO_API_BASE=$(echo "$FENO_API_BASE" | sed 's|/*$||')
  _debug FENO_API_BASE "$FENO_API_BASE"

  _saveaccountconf_mutable FENO_API_KEY "$FENO_API_KEY"
  if [ "$FENO_API_BASE" != "$FENO_API_BASE_DEFAULT" ]; then
    _saveaccountconf_mutable FENO_API_BASE "$FENO_API_BASE"
  fi
  return 0
}

# Find the FENO zone holding $1 (an FQDN), and the record name RELATIVE to that zone.
#
# This relative-vs-absolute conversion is the classic bug in DNS API plugins. The FENO API
# (like Bunny underneath it) stores record names relative to the zone - "" is the apex,
# "_acme-challenge" is the challenge record of the zone itself - while ACME hands us the
# absolute "_acme-challenge.www.kunde.no". Sending the absolute name creates
# "_acme-challenge.www.kunde.no.kunde.no", which resolves to NXDOMAIN and is maddening to
# spot, because the API call itself succeeds.
#
# The zone is not guessed from a label count either: ".no" carries both plain second-level
# names and delegated sub-zones, so labels are peeled off one at a time and every candidate
# is checked against the API. The first candidate this key can actually see is the zone;
# everything to its left is the relative name.
#
# Sets _domain (the zone) and _sub_domain (the relative record name).
_get_root() {
  domain=$1
  i=1
  p=1

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      # Ran out of labels without a match.
      return 1
    fi

    if ! _feno_rest GET "v1/domains/$h"; then
      return 1
    fi

    # A revoked or wrongly scoped key must not look like "domain not found", or the loop
    # walks all the way up to the TLD and then reports a thoroughly misleading error.
    if _feno_code=$(_feno_auth_error); then
      _err "FENO rejected the API key ($_feno_code)."
      _err "Check FENO_API_KEY, that the key is still active, and that it carries the acme:write scope."
      return 1
    fi

    if _contains "$response" '"success":true'; then
      _domain="$h"
      if [ "$i" = "1" ]; then
        # The fulldomain IS the zone. DNS alias mode can point the challenge at a delegated
        # _acme-challenge zone, and then the record belongs at the apex - taking the first
        # label here would create it at "kunde.kunde.no" instead.
        _sub_domain=""
      else
        _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-"$p")
      fi
      return 0
    fi

    p="$i"
    i=$(_math "$i" + 1)
  done
  return 1
}

# Echo the machine error code when $response is one of the /v1 auth-layer refusals; fail otherwise.
#
# These are the codes the /v1 auth layer actually emits. An earlier version matched on
# UNAUTHORIZED / MISSING_TOKEN, which /v1 never sends - so a revoked, expired, IP-blocked,
# under-scoped or rate-limited key was indistinguishable from "no such domain", and the zone
# walk above blamed the domain instead of the key.
_feno_auth_error() {
  for _fcode in AUTH_REQUIRED INVALID_API_KEY API_KEY_INACTIVE API_KEY_EXPIRED \
    IP_NOT_ALLOWED ACCOUNT_NOT_FOUND ACCOUNT_SUSPENDED INSUFFICIENT_SCOPE RATE_LIMITED; do
    if _contains "$response" "\"code\":\"$_fcode\""; then
      printf "%s" "$_fcode"
      return 0
    fi
  done
  return 1
}

# Echo the id of the TXT record with relative name $1 and value $2, or nothing at all.
#
# The JSON array is split at "{" so each record lands on its own line - the payload has no
# nested objects, so that is enough, and it spares the customer a jq dependency. Matching is
# done with quoted "case" patterns rather than grep: quoting makes every character literal,
# so no "grep -F" is needed (Solaris /usr/bin/grep has no -F). The quotes inside the patterns
# are load-bearing - they make "_acme-challenge" match the record named exactly that, and
# NOT "_acme-challenge.www".
#
# DNS names are case-insensitive, the challenge value is not, so only the name is folded.
_feno_find_record_id() {
  _find_name=$1
  _find_value=$2

  _find_name_lower=$(printf "%s" "$_find_name" | _lower_case)

  _line=$(printf "%s\n" "$response" | tr '{' '\n' | while IFS= read -r _fline; do
    case "$_fline" in
    *"\"value\":\"$_find_value\""*)
      case "$_fline" in
      *'"type":"TXT"'*)
        case "$(printf "%s" "$_fline" | _lower_case)" in
        *"\"name\":\"$_find_name_lower\""*) printf "%s\n" "$_fline" ;;
        esac
        ;;
      esac
      ;;
    esac
  done | _head_n 1)

  if [ -z "$_line" ]; then
    return 0
  fi

  # The id is a number from Bunny, but some proxies quote it - tolerate both.
  printf "%s" "$_line" | _egrep_o '"id":[^,}]*' | _head_n 1 | cut -d : -f 2 | tr -d '" '
}

# $1 = HTTP method, $2 = path without a leading slash, $3 = body (POST/PUT only).
# Leaves the raw body in $response, as the rest of acme.sh expects.
_feno_rest() {
  _feno_method=$1
  _feno_path=$2
  _feno_body=$3

  export _H1="Authorization: Bearer $FENO_API_KEY"
  export _H2="Content-Type: application/json"
  export _H3="Accept: application/json"

  if [ "$_feno_method" = "GET" ]; then
    if ! response="$(_get "$FENO_API_BASE/$_feno_path")"; then
      _err "FENO API request failed: $_feno_method $_feno_path"
      return 1
    fi
  else
    if ! response="$(_post "$_feno_body" "$FENO_API_BASE/$_feno_path" "" "$_feno_method" "application/json")"; then
      _err "FENO API request failed: $_feno_method $_feno_path"
      return 1
    fi
  fi

  _debug2 response "$response"
  return 0
}
