#!/usr/bin/env sh

METANAME_ENDPOINT="https://metaname.net/api/1.1"

########  Public functions #####################

# Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
# Used to add txt record
#
# Ref: https://metaname.net/api/1.1/doc
#
dns_metaname_add() {
  fulldomain=$1
  txtvalue=$2

  METANAME_ACCOUNT="${METANAME_ACCOUNT:-$(_readaccountconf_mutable METANAME_ACCOUNT)}"
  METANAME_KEY="${METANAME_KEY:-$(_readaccountconf_mutable METANAME_KEY)}"

  if [ -z "$METANAME_ACCOUNT" ]; then
    METANAME_KEY=""
    _err "You didn't specify the Metaname account "
    return 1
  fi

  if [ -z "$METANAME_KEY" ]; then
    METANAME_ACCOUNT=""
    _err "You didn't specify the Metaname API key "
    return 1
  fi

  # Save account details to account conf file.
  _saveaccountconf_mutable METANAME_ACCOUNT "$METANAME_ACCOUNT"
  _saveaccountconf_mutable METANAME_KEY "$METANAME_KEY"

  if ! _get_root "$fulldomain" "$METANAME_ACCOUNT" "$METANAME_KEY"; then
    _err "invalid domain"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  data="{\"name\":\"$_sub_domain\",\"type\":\"TXT\",\"data\":\"$txtvalue\"}"

  # Add the txtvalue TXT Record
  # https://metaname.net/api/1.1/doc#create_dns_record
  if _metaname_rpc "create_dns_record" "$account" "$key" "$_domain" "$data"; then
    _info "validation value added"
    return 0
  else
    return 1
  fi
}

# Usage: fulldomain txtvalue
# Used to remove the txt record after validation
dns_metaname_rm() {
  fulldomain=$1
  txtvalue=$2

  METANAME_ACCOUNT="${METANAME_ACCOUNT:-$(_readaccountconf_mutable METANAME_ACCOUNT)}"
  METANAME_KEY="${METANAME_KEY:-$(_readaccountconf_mutable METANAME_KEY)}"

  if [ -z "$METANAME_ACCOUNT" ]; then
    METANAME_KEY=""
    _err "You didn't specify the Metaname account "
    return 1
  fi

  if [ -z "$METANAME_KEY" ]; then
    METANAME_ACCOUNT=""
    _err "You didn't specify the Metaname API key "
    return 1
  fi

  # Save account details to account conf file.
  _saveaccountconf_mutable METANAME_ACCOUNT "$METANAME_ACCOUNT"
  _saveaccountconf_mutable METANAME_KEY "$METANAME_KEY"

  if ! _get_root "$fulldomain" "$METANAME_ACCOUNT" "$METANAME_KEY"; then
    _err "invalid domain"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  # Get existing records
  # https://metaname.net/api/1.1/doc#dns_zone
  _metaname_rpc "dns_zone" "$account" "$key" "$_domain" || return 1

  # Find reference for matching record(s) to delete
  expected_name=$(printf '\{[^{]*?"name":"%s",.*?}' "$_sub_domain")
  expected_data=$(printf '\{[^{]*?"data":"%s",.*?}' "$txtvalue")
  found=
  for record in $(echo "$response" | _egrep_o "$expected_name"); do

    # Check the text value matches
    echo "$record" | grep -qE "$expected_data" 2>/dev/null || continue

    # This gets us the quoted reference number: need to strip the quotes
    ref=$(_getfield "$(echo "$record" | _egrep_o "\"reference\":\"[^\"]*\"")" 2 :)
    ref="${ref%\"}"
    ref="${ref#\"}"

    # Delete matching record
    # https://metaname.net/api/1.1/doc#delete_dns_record
    _debug "deleting matching record with reference: $ref"
    if _metaname_rpc "delete_dns_record" "$account" "$key" "$_domain" "$ref"; then
      _info "validation record removed"
      found=1
    else
      _err "error removing validation record, aborting"
      return 1
    fi
  done

  if [ -z $found ]; then
    _err "no validation record found, aborting"
    return 1
  fi

  return 0
}

###################  Private functions below ##################################

_metaname_rpc() {
  cmd=$1
  shift

  # Assume parameters starting with a "{" are dictionaries; quote all others
  comma=
  params=
  for param in "$@"; do
    if _startswith "$param" "{"; then
      params="$params$comma$param"
    else
      params="$params$comma$(printf "\"%s\"" "$param")"
    fi
    comma=,
  done

  # TODO: Get random ID? Can't use $RANDOM as that is not POSIX...
  id=0
  data="{\"jsonrpc\":\"2.0\", \"id\": \"$id\", \"method\": \"$cmd\", \"params\":[$params]}"
  export _H1="accept: application/json"
  export _H2="Content-Type: application/json"

  # clear headers from previous request to avoid getting wrong http code on timeouts
  :>"$HTTP_HEADER"
  _secure_debug2 "data $data"
  response="$(_post "$data" "$METANAME_ENDPOINT" "" "POST")"

  _ret="$?"
  _secure_debug2 "response $response"
  _code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\\r\\n")"
  _debug "http response code $_code"
  if [ "$_ret" != "0" ] || [ -z "$_code" ] || [ "$_code" != "200" ]; then
    _err "calling $METANAME_ENDPOINT failed"
    return 1
  fi

  response="$(echo "$response" | _normalizeJson)"
  msg=$(_getfield "$(echo "$response" | _egrep_o "\"message\":\"[^\"]*\"")" 2 :)
  if [ -n "$msg" ]; then
    _err "server returned error on call to $cmd: $msg"
    return 1
  fi

  response=$(echo "$response" | sed 's/.*"result"\:\[/\[/' | head -c -2)
  return 0
}

_get_root() {
  domain=$1
  account=$2
  key=$3
  i=2
  p=1

  # https://metaname.net/api/1.1/doc#domain_names
  _metaname_rpc "domain_names" "$account" "$key" || return 1

  # Find matching domain name in JSON response
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    if [ -z "$h" ]; then
      return 1
    fi

    if _contains "$response" "\"name\":\"$h\"" >/dev/null; then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
      _domain=$h
      return 0
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}
