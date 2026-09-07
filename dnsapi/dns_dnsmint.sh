#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_dnsmint_info='DNSMint.com
 DNSMint mints hostnames on domains it operates and serves from its own
 authoritative nameservers, so records are published through its API rather
 than a zone you run.
Site: dnsmint.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_dnsmint
Options:
 DNSMINT_API_KEY API key. dns01:write is enough to issue certificates.
Issues: github.com/dnsmint/acme.sh
Author: DNSMint
'

DNSMint_Api="https://dnsmint.com/api"

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

  # An ACME challenge goes to the DNS-01 endpoint, which derives the hostname
  # itself and needs only dns01:write. Any other name is an ordinary record
  # under a hostname, which is a different endpoint and a wider scope.
  if _startswith "$fulldomain" "_acme-challenge."; then
    if _dnsmint_challenge present "$fulldomain" "$txtvalue"; then
      _info "Added, OK"
      return 0
    fi
    return 1
  fi

  if _dnsmint_record_add "$fulldomain" "$txtvalue"; then
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

  if _startswith "$fulldomain" "_acme-challenge."; then
    if _dnsmint_challenge cleanup "$fulldomain" "$txtvalue"; then
      _info "Removed, OK"
      return 0
    fi
    return 1
  fi

  if _dnsmint_record_rm "$fulldomain" "$txtvalue"; then
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

_dnsmint_headers() {
  export _H1="Authorization: Bearer $DNSMINT_API_KEY"
  export _H2="Accept: application/json"
  export _H3="Content-Type: application/json"
}

# One request. Sets $response and $_code; returns non-zero on a transport error.
_dnsmint_rest() {
  _m="$1"
  _ep="$2"
  _data="$3"

  _dnsmint_headers
  if [ "$_m" = "GET" ]; then
    response="$(_get "$DNSMint_Api$_ep")"
  else
    _secure_debug2 _data "$_data"
    response="$(_post "$_data" "$DNSMint_Api$_ep" "" "$_m")"
  fi
  _ret="$?"
  _code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\\r\\n")"
  _debug "http response code $_code"
  _debug2 response "$response"
  if [ "$_ret" != "0" ]; then
    _err "error $_ep"
    return 1
  fi
  case "$_code" in
    2*) return 0 ;;
    *)
      # The API says why in the body - a key narrowed to another hostname, a
      # name that is not live - and that is more use than the status alone.
      _err "error $_ep: HTTP $_code $response"
      return 1
      ;;
  esac
}

# The DNS-01 endpoint. It derives the hostname from the challenge name, so
# there is no zone to look up and no record id to track: the value published
# is the value removed.
_dnsmint_challenge() {
  _action="$1"
  _fqdn="$2"
  _value="$3"
  _dnsmint_rest POST "/httpreq/$_action" "{\"fqdn\":\"$_fqdn\",\"value\":\"$_value\"}"
}

# Everything below here is for names that are not ACME challenges. A record
# under a hostname is addressed by the hostname's id and a name relative to
# it, so the hostname has to be found first.
_dnsmint_host() {
  _name="$1"
  _host_id=""
  _host_sub=""

  if ! _dnsmint_rest GET "/v1/hostnames?limit=500"; then
    return 1
  fi

  for _h in $(echo "$response" | _egrep_o '"hostname":"[^"]*"' | cut -d'"' -f4); do
    case "$_name" in
      *".$_h")
        # Longest suffix wins, so a.b.example.dev prefers b.example.dev over
        # example.dev when both are hostnames on the account.
        if [ "${#_h}" -gt "${#_host_sub}" ]; then
          _host_sub="$_h"
        fi
        ;;
    esac
  done

  if [ -z "$_host_sub" ]; then
    _err "$_name is not under a hostname on this account"
    return 1
  fi

  # The id sits next to the hostname in the same object.
  _host_id="$(echo "$response" | _egrep_o "\"id\":\"[^\"]*\",\"hostname\":\"$_host_sub\"" | cut -d'"' -f4)"
  if [ -z "$_host_id" ]; then
    _err "could not read the id for $_host_sub"
    return 1
  fi

  _record_name="${_name%".$_host_sub"}"
  _debug _host_sub "$_host_sub"
  _debug _record_name "$_record_name"
  return 0
}

_dnsmint_record_add() {
  _name="$1"
  _value="$2"

  if ! _dnsmint_host "$_name"; then
    return 1
  fi
  _dnsmint_rest POST "/v1/hostnames/$_host_id/records" \
    "{\"name\":\"$_record_name\",\"type\":\"TXT\",\"text\":\"$_value\"}"
}

_dnsmint_record_rm() {
  _name="$1"
  _value="$2"

  if ! _dnsmint_host "$_name"; then
    return 1
  fi
  if ! _dnsmint_rest GET "/v1/hostnames/$_host_id/records"; then
    return 1
  fi

  # Records come back as {"id":...,"name":"<fqdn>","type":"TXT","ttl":...,
  # "data":{...,"text":["<value>"]}}. Match on the value so a name holding
  # several TXT records loses only the one that was added.
  _rid="$(echo "$response" | sed 's/},{/}\n{/g' | grep -F "\"$_value\"" | _egrep_o '"id":"[^"]*"' | cut -d'"' -f4 | _head_n 1)"
  if [ -z "$_rid" ]; then
    _info "Record already gone, nothing to remove"
    return 0
  fi
  _dnsmint_rest DELETE "/v1/hostnames/$_host_id/records/$_rid" ""
}
