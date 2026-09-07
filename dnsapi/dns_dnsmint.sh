#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_dnsmint_info='DNSMint.com
 DNSMint mints hostnames on domains it operates and serves from its own
 authoritative nameservers, so the challenge is published through its API
 rather than a zone you run.
Site: dnsmint.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_dnsmint
Options:
 DNSMINT_API_KEY API key carrying the dns01:write scope
Issues: github.com/dnsmint/acme.sh
Author: DNSMint
'

DNSMint_Api="https://dnsmint.com/api/httpreq"

########  Public functions #####################

#Usage: dns_dnsmint_add _acme-challenge.q7k4m2.example.dev "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_dnsmint_add() {
  fulldomain=$1
  txtvalue=$2

  _info "Using DNSMint"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  if ! _dnsmint_key; then
    return 1
  fi

  if _dnsmint_rest present "$fulldomain" "$txtvalue"; then
    _info "Added, OK"
    return 0
  fi
  return 1
}

#Usage: dns_dnsmint_rm _acme-challenge.q7k4m2.example.dev "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_dnsmint_rm() {
  fulldomain=$1
  txtvalue=$2

  _info "Using DNSMint"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  if ! _dnsmint_key; then
    return 1
  fi

  if _dnsmint_rest cleanup "$fulldomain" "$txtvalue"; then
    _info "Removed, OK"
    return 0
  fi
  return 1
}

####################  Private functions below ##################################

_dnsmint_key() {
  DNSMINT_API_KEY="${DNSMINT_API_KEY:-$(_readaccountconf_mutable DNSMINT_API_KEY)}"
  if [ -z "$DNSMINT_API_KEY" ]; then
    DNSMINT_API_KEY=""
    _err "You did not specify DNSMINT_API_KEY yet."
    _err "Create a key with the dns01:write scope at https://dnsmint.com/dashboard"
    _err "e.g."
    _err "export DNSMINT_API_KEY=dnsm_xxxxxxxxxxxx_xxxxxxxx"
    return 1
  fi
  _saveaccountconf_mutable DNSMINT_API_KEY "$DNSMINT_API_KEY"
  return 0
}

# DNSMint derives the hostname from the challenge name, so there is no zone to
# look up and no record id to track: the value published is the value removed.
_dnsmint_rest() {
  action="$1"
  fqdn="$2"
  value="$3"

  export _H1="Authorization: Bearer $DNSMINT_API_KEY"
  export _H2="Accept: application/json"
  export _H3="Content-Type: application/json"

  data="{\"fqdn\":\"$fqdn\",\"value\":\"$value\"}"
  _secure_debug2 data "$data"

  response="$(_post "$data" "$DNSMint_Api/$action" "" "POST")"
  _ret="$?"
  _code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\\r\\n")"
  _debug "http response code $_code"
  _debug2 response "$response"

  if [ "$_ret" != "0" ]; then
    _err "error $action"
    return 1
  fi
  case "$_code" in
    2*) return 0 ;;
    *)
      # The API says why in the body - a key narrowed to another hostname, a
      # name that is not live - and that is more use than the status alone.
      _err "error $action: HTTP $_code $response"
      return 1
      ;;
  esac
}
