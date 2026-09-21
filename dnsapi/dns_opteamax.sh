#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_opteamax_info='Opteamax.de
Site: opteamax.de
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_opteamax
Options:
 OPTEAMAX_Token API token. Create it in the customer panel under "API-Tokens"; it starts with "oxt_".
 OPTEAMAX_Api API endpoint. Default "https://api.opteam.ax/api/v2". Optional.
Issues: github.com/acmesh-official/acme.sh/issues/7245
Author: Jens Ott <jo@opteamax.de>
'

OPTEAMAX_Api_Default="https://api.opteam.ax/api/v2"

######## Public functions #####################

#Usage: dns_opteamax_add _acme-challenge.www.domain.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_opteamax_add() {
  fulldomain=$1
  txtvalue=$2
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  if ! _opteamax_init; then
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    return 1
  fi
  _debug _domain "$_domain"
  _debug _domain_id "$_domain_id"

  _info "Adding the TXT record"
  _opteamax_body="{\"type\":\"TXT\",\"name\":\"$fulldomain.\",\"content\":\"$txtvalue\",\"ttl\":300}"
  if ! _opteamax_rest POST "/dns/domains/$_domain_id/records/" "$_opteamax_body"; then
    return 1
  fi
  if ! _contains "$response" "data_id"; then
    _err "Could not add the TXT record: $response"
    return 1
  fi

  _info "TXT record added"
  return 0
}

#Usage: dns_opteamax_rm _acme-challenge.www.domain.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_opteamax_rm() {
  fulldomain=$1
  txtvalue=$2
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  if ! _opteamax_init; then
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    return 1
  fi
  _debug _domain "$_domain"
  _debug _domain_id "$_domain_id"

  _debug "Getting the record id"
  if ! _opteamax_rest GET "/dns/domains/$_domain_id/records/"; then
    return 1
  fi

  # Only this challenge's record may go: a wildcard certificate puts two TXT
  # values on the same name, and acme.sh removes them one call at a time.
  # PowerDNS hands TXT content back in wire format, so the value arrives inside
  # escaped quotes ("content": "\"<value>\""); matching from the field name up
  # to the next field keeps the value pinned to the content field without
  # spelling out those backslashes. _head_n 1 guarantees a single id even if an
  # aborted earlier run left the same value behind twice.
  _record_id=$(
    echo "$response" | _opteamax_split |
      grep '"type": *"TXT"' |
      grep "\"name\": *\"$(_opteamax_re "$fulldomain")\.\"" |
      grep "\"content\":[^,]*$txtvalue" |
      _egrep_o '"data_id": *"[^"]*"' |
      sed 's/.*"data_id": *"//;s/"$//' |
      _head_n 1
  )
  _debug _record_id "$_record_id"

  if [ -z "$_record_id" ]; then
    _info "No such TXT record, nothing to remove."
    return 0
  fi

  _info "Removing the TXT record"
  if ! _opteamax_rest DELETE "/dns/domains/$_domain_id/records/$_record_id/"; then
    return 1
  fi

  _info "TXT record removed"
  return 0
}

#################### Private functions below ##################################

# Read and check the credentials, and remember them for the renewal.
_opteamax_init() {
  OPTEAMAX_Token="${OPTEAMAX_Token:-$(_readaccountconf_mutable OPTEAMAX_Token)}"
  OPTEAMAX_Api="${OPTEAMAX_Api:-$(_readaccountconf_mutable OPTEAMAX_Api)}"

  if [ -z "$OPTEAMAX_Token" ]; then
    _err "You have not set OPTEAMAX_Token yet."
    _err "Create an API token in the customer panel under \"API-Tokens\" and export it:"
    _err "export OPTEAMAX_Token=\"oxt_...\""
    return 1
  fi

  if [ -z "$OPTEAMAX_Api" ]; then
    OPTEAMAX_Api="$OPTEAMAX_Api_Default"
  else
    # A trailing slash would make every request path a double slash, which
    # Django answers with a redirect that drops the request body.
    OPTEAMAX_Api=$(echo "$OPTEAMAX_Api" | sed 's|/*$||')
    _saveaccountconf_mutable OPTEAMAX_Api "$OPTEAMAX_Api"
  fi
  _saveaccountconf_mutable OPTEAMAX_Token "$OPTEAMAX_Token"
  return 0
}

#_acme-challenge.www.domain.com
#returns
# _domain=domain.com
# _domain_id=1234
_get_root() {
  domain=$1

  # One request for the account's zones, then the name is walked up against
  # them locally: the longest match wins, so a delegated subzone beats its
  # parent.
  if ! _opteamax_rest GET "/dns/domains/"; then
    return 1
  fi
  _zones=$(echo "$response" | _opteamax_split)

  i=1
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    if [ -z "$h" ]; then
      break
    fi

    _domain_id=$(
      echo "$_zones" |
        grep "\"domain\": *\"$(_opteamax_re "$h")\.\{0,1\}\"" |
        _egrep_o '"domain_id": *[0-9]*' |
        tr -d ' ' | cut -d : -f 2 | _head_n 1
    )
    if [ "$_domain_id" ]; then
      _domain="$h"
      return 0
    fi

    i=$(_math "$i" + 1)
  done

  # Only reached when the walk ran out of labels -- a failed request returns
  # above, so this really does mean the account holds no zone for the name.
  _err "Could not find a zone for $domain in your Opteamax account."
  return 1
}

# Put one JSON object per line so a record's id can be read off the same line
# as its name and content.
_opteamax_split() {
  sed 's/}, *{/}#{/g' | tr '#' '\n'
}

# Escape a domain name for use in a grep pattern: the dots are literal.
_opteamax_re() {
  echo "$1" | sed 's/\./\\./g'
}

# method endpoint [body]
_opteamax_rest() {
  m="$1"
  ep="$2"
  data="$3"
  _debug "$ep"

  export _H1="Authorization: Bearer $OPTEAMAX_Token"
  export _H2="Content-Type: application/json"
  export _H3="Accept: application/json"

  if [ "$m" = "GET" ]; then
    response="$(_get "$OPTEAMAX_Api$ep")"
  else
    _debug data "$data"
    response="$(_post "$data" "$OPTEAMAX_Api$ep" "" "$m")"
  fi

  if [ "$?" != "0" ]; then
    _err "Error talking to $OPTEAMAX_Api$ep"
    return 1
  fi
  _debug2 response "$response"

  # A proxy or gateway error comes back as an HTML page with a 5xx status, and
  # the http helpers only report transport failures -- so without this check the
  # caller parses an error page as data and reports something misleading, such
  # as the zone not existing.
  case "$response" in
  "{"* | "["*) ;;
  *)
    _err "Unexpected response from $OPTEAMAX_Api$ep (not JSON):"
    _err "$(echo "$response" | _head_n 3)"
    return 1
    ;;
  esac

  # The API answers an authentication or permission problem with a JSON body
  # and a 4xx status; the http helpers only report transport errors, so the
  # body is what tells us the call was refused.
  if _contains "$response" '"detail"'; then
    _err "The API refused the request: $response"
    return 1
  fi

  return 0
}
