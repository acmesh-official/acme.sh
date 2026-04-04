#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_exoscale_info='Exoscale.com
Site: Exoscale.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_exoscale
Options:
 EXOSCALE_API_KEY API Key
 EXOSCALE_SECRET_KEY API Secret key
'

EXOSCALE_API="https://api-ch-gva-2.exoscale.com/v2"

########  Public functions  ########

# Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
# Used to add txt record
dns_exoscale_add() {
  fulldomain=$1
  txtvalue=$2

  _debug "Using Exoscale DNS v2 API"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  if ! _check_auth; then
    return 1
  fi

  root_domain_id=$(_get_root_domain_id "$fulldomain")
  if [ -z "$root_domain_id" ]; then
    _err "Unable to determine root domain ID for $fulldomain"
    return 1
  fi
  _debug root_domain_id "$root_domain_id"

  # Always get the subdomain part first
  sub_domain=$(_get_sub_domain "$fulldomain" "$root_domain_id")
  _debug sub_domain "$sub_domain"

  # Build the record name properly
  if [ -z "$sub_domain" ]; then
    record_name="_acme-challenge"
  else
    record_name="_acme-challenge.$sub_domain"
  fi

  payload=$(printf '{"name":"%s","type":"TXT","content":"%s","ttl":120}' "$record_name" "$txtvalue")
  _debug payload "$payload"

  response=$(_exoscale_rest POST "/dns-domain/${root_domain_id}/record" "$payload")
  if _contains "$response" "\"id\""; then
    _info "TXT record added successfully."
    return 0
  else
    _err "Error adding TXT record: $response"
    return 1
  fi
}

dns_exoscale_rm() {
  fulldomain=$1

  _debug "Using Exoscale DNS v2 API for removal"
  _debug fulldomain "$fulldomain"

  if ! _check_auth; then
    return 1
  fi

  root_domain_id=$(_get_root_domain_id "$fulldomain")
  if [ -z "$root_domain_id" ]; then
    _err "Unable to determine root domain ID for $fulldomain"
    return 1
  fi

  record_name="_acme-challenge"
  sub_domain=$(_get_sub_domain "$fulldomain" "$root_domain_id")
  if [ -n "$sub_domain" ]; then
    record_name="_acme-challenge.$sub_domain"
  fi

  record_id=$(_find_record_id "$root_domain_id" "$record_name")
  if [ -z "$record_id" ]; then
    _err "TXT record not found for deletion."
    return 1
  fi

  response=$(_exoscale_rest DELETE "/dns-domain/$root_domain_id/record/$record_id")
  if _contains "$response" "\"state\":\"success\""; then
    _info "TXT record deleted successfully."
    return 0
  else
    _err "Error deleting TXT record: $response"
    return 1
  fi
}

########  Private helpers  ########

_check_auth() {
  EXOSCALE_API_KEY="${EXOSCALE_API_KEY:-$(_readaccountconf_mutable EXOSCALE_API_KEY)}"
  EXOSCALE_SECRET_KEY="${EXOSCALE_SECRET_KEY:-$(_readaccountconf_mutable EXOSCALE_SECRET_KEY)}"
  if [ -z "$EXOSCALE_API_KEY" ] || [ -z "$EXOSCALE_SECRET_KEY" ]; then
    _err "EXOSCALE_API_KEY and EXOSCALE_SECRET_KEY must be set."
    return 1
  fi
  _saveaccountconf_mutable EXOSCALE_API_KEY "$EXOSCALE_API_KEY"
  _saveaccountconf_mutable EXOSCALE_SECRET_KEY "$EXOSCALE_SECRET_KEY"
  return 0
}

_get_root_domain_id() {
  domain=$1
  i=1
  while true; do
    candidate=$(printf "%s" "$domain" | cut -d . -f "${i}-100")
    [ -z "$candidate" ] && return 1
    _debug "Trying root domain candidate: $candidate"
    domains=$(_exoscale_rest GET "/dns-domain")
    # Extract from dns-domains array
    result=$(echo "$domains" | _egrep_o '"dns-domains":\[.*\]' | _egrep_o '\{"id":"[^"]*","created-at":"[^"]*","unicode-name":"[^"]*"\}' | while read -r item; do
      name=$(echo "$item" | _egrep_o '"unicode-name":"[^"]*"' | cut -d'"' -f4)
      id=$(echo "$item" | _egrep_o '"id":"[^"]*"' | cut -d'"' -f4)
      if [ "$name" = "$candidate" ]; then
        echo "$id"
        break
      fi
    done)
    if [ -n "$result" ]; then
      echo "$result"
      return 0
    fi
    i=$(_math "$i" + 1)
  done
}

_get_sub_domain() {
  fulldomain=$1
  root_id=$2
  root_info=$(_exoscale_rest GET "/dns-domain/$root_id")
  _debug root_info "$root_info"
  root_name=$(echo "$root_info" | _egrep_o "\"unicode-name\":\"[^\"]*\"" | cut -d\" -f4)
  sub=${fulldomain%%."$root_name"}

  if [ "$sub" = "_acme-challenge" ]; then
    echo ""
  else
    # Remove _acme-challenge. prefix to get the actual subdomain
    echo "${sub#_acme-challenge.}"
  fi
}

_find_record_id() {
  root_id=$1
  name=$2
  records=$(_exoscale_rest GET "/dns-domain/$root_id/record")

  # Convert search name to lowercase for case-insensitive matching
  name_lower=$(echo "$name" | tr '[:upper:]' '[:lower:]')

  echo "$records" | _egrep_o '\{[^}]*"name":"[^"]*"[^}]*\}' | while read -r record; do
    record_name=$(echo "$record" | _egrep_o '"name":"[^"]*"' | cut -d'"' -f4)
    record_name_lower=$(echo "$record_name" | tr '[:upper:]' '[:lower:]')
    if [ "$record_name_lower" = "$name_lower" ]; then
      echo "$record" | _egrep_o '"id":"[^"]*"' | _head_n 1 | cut -d'"' -f4
      break
    fi
  done
}

_exoscale_sign() {
  k=$1
  shift
  hex_key=$(printf %b "$k" | _hex_dump | tr -d ' ')
  printf %s "$@" | _hmac sha256 "$hex_key"
}

_exoscale_rest() {
  method=$1
  path=$2
  data=$3

  url="${EXOSCALE_API}${path}"
  expiration=$(_math "$(date +%s)" + 300) # 5m from now

  # Build the message with the actual body or empty line
  message=$(printf "%s %s\n%s\n\n\n%s" "$method" "/v2$path" "$data" "$expiration")
  signature=$(_exoscale_sign "$EXOSCALE_SECRET_KEY" "$message" | _base64)
  auth="EXO2-HMAC-SHA256 credential=${EXOSCALE_API_KEY},expires=${expiration},signature=${signature}"

  _debug "API request: $method $url"
  _debug "Signed message: [$message]"
  _debug "Authorization header: [$auth]"

  export _H1="Accept: application/json"
  export _H2="Authorization: ${auth}"

  if [ "$data" ] || [ "$method" = "DELETE" ]; then
    export _H3="Content-Type: application/json"
    _debug data "$data"
    response="$(_post "$data" "$url" "" "$method")"
  else
    response="$(_get "$url" "" "" "$method")"
  fi

  # shellcheck disable=SC2181
  if [ "$?" -ne 0 ]; then
    _err "error $url"
    return 1
  fi
  _debug2 response "$response"
  echo "$response"
  return 0
}
