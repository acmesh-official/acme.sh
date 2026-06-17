#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_qc_info='QUIC.cloud
Site: quic.cloud
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_qc
Options:
 QC_API_KEY QC API Key
 QC_API_EMAIL Your account email
'

QC_Api="https://api.quic.cloud/v2"

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_qc_add() {
  fulldomain=$1
  txtvalue=$2

  _debug "Enter dns_qc_add fulldomain: $fulldomain, txtvalue: $txtvalue"
  QC_API_KEY="${QC_API_KEY:-$(_readaccountconf_mutable QC_API_KEY)}"
  QC_API_EMAIL="${QC_API_EMAIL:-$(_readaccountconf_mutable QC_API_EMAIL)}"

  if [ "$QC_API_KEY" ]; then
    _saveaccountconf_mutable QC_API_KEY "$QC_API_KEY"
  else
    _err "You didn't specify a QUIC.cloud api key as QC_API_KEY."
    _err "You can get yours from here https://my.quic.cloud/up/api."
    return 1
  fi

  if ! _contains "$QC_API_EMAIL" "@"; then
    _err "It seems that the QC_API_EMAIL=$QC_API_EMAIL is not a valid email address."
    _err "Please check and retry."
    return 1
  fi
  #save the api key and email to the account conf file.
  _saveaccountconf_mutable QC_API_EMAIL "$QC_API_EMAIL"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain during add"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting txt records"
  _qc_rest GET "zones/${_domain_id}/records"

  if ! echo "$response" | tr -d " " | grep \"success\":true >/dev/null; then
    _err "Error failed response from QC GET: $response"
    return 1
  fi

  # For wildcard cert, the main root domain and the wildcard domain have the same txt subdomain name, so
  # we can not use updating anymore.
  #  count=$(printf "%s\n" "$response" | _egrep_o "\"count\":[^,]*" | cut -d : -f 2)
  #  _debug count "$count"
  #  if [ "$count" = "0" ]; then
  _info "Adding txt record"
  if _qc_rest POST "zones/$_domain_id/records" "{\"type\":\"TXT\",\"name\":\"$fulldomain\",\"content\":\"$txtvalue\",\"ttl\":1800}"; then
    if _contains "$response" "$txtvalue"; then
      _info "Added txt record, OK"
      return 0
    elif _contains "$response" "Same record already exists"; then
      _info "txt record already exists, OK"
      return 0
    else
      _err "Add txt record error: $response"
      return 1
    fi
  fi
  _err "Add txt record error: POST failed: $response"
  return 1

}

#fulldomain txtvalue
dns_qc_rm() {
  fulldomain=$1
  txtvalue=$2

  _debug "Enter dns_qc_rm fulldomain: $fulldomain, txtvalue: $txtvalue"
  QC_API_KEY="${QC_API_KEY:-$(_readaccountconf_mutable QC_API_KEY)}"
  QC_API_EMAIL="${QC_API_EMAIL:-$(_readaccountconf_mutable QC_API_EMAIL)}"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain during rm"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting txt records"
  _qc_rest GET "zones/${_domain_id}/records"

  if ! echo "$response" | tr -d " " | grep \"success\":true >/dev/null; then
    _err "Error rm GET response: $response"
    return 1
  fi

  _debug "Pre-jq response:" "$response"
  # Do not use jq or subsequent code
  #response=$(echo "$response" | jq ".result[] | select(.id) | select(.content == \"$txtvalue\") | select(.type == \"TXT\")")
  #_debug "get txt response" "$response"
  #if [ "${response}" = "" ]; then
  #  _info "Don't need to remove txt records."
  #  return 0
  #fi
  #record_id=$(echo "$response" | grep \"id\" | awk -F ' ' '{print $2}' | sed 's/,$//')
  #_debug "txt record_id" "$record_id"
  #Instead of jq
  array=$(echo "$response" | grep -o '\[[^]]*\]' | sed 's/^\[\(.*\)\]$/\1/')
  if [ -z "$array" ]; then
    _err "Expected array in QC response: $response"
    return 1
  fi
  # Temporary file to hold matched content (one per line)
  tmpfile=$(_mktemp)
  echo "$array" | grep -o '{[^}]*}' | sed 's/^{//;s/}$//' >"$tmpfile"
  record_id=""

  while IFS= read -r obj || [ -n "$obj" ]; do
    if echo "$obj" | grep -q '"TXT"' && echo "$obj" | grep -q '"id"' && echo "$obj" | grep -q "$txtvalue"; then
      _debug "response includes" "$obj"
      record_id=$(echo "$obj" | sed 's/^\"id\":\([0-9]\+\).*/\1/')
      break
    fi
  done <"$tmpfile"

  rm "$tmpfile"

  if [ -z "$record_id" ]; then
    _info "TXT record, or $txtvalue not found, nothing to remove"
    return 0
  fi

  #End of jq replacement
  if ! _qc_rest DELETE "zones/$_domain_id/records/$record_id"; then
    _info "Delete txt record error."
    return 1
  fi

  _info "TXT Record ID: $record_id successfully deleted"
  return 0

}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
# _domain_id=sdjkglgdfewsdfg
_get_root() {
  domain=$1
  i=1
  p=1

  h=$(printf "%s" "$domain" | cut -d . -f2-)
  _debug h "$h"
  if [ -z "$h" ]; then
    _err "$h ($domain) is an invalid domain"
    return 1
  fi

  if ! _qc_rest GET "zones"; then
    _err "qc_rest failed"
    return 1
  fi

  if _contains "$response" "\"name\":\"$h\"" || _contains "$response" "\"name\":\"$h.\""; then
    _domain_id=$h
    if [ "$_domain_id" ]; then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-"$p")
      _domain=$h
      return 0
    fi
    _err "Empty domain_id $h"
    return 1
  fi
  _err "Missing domain_id $h"
  return 1
}

_qc_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"

  email_trimmed=$(echo "$QC_API_EMAIL" | tr -d '"')
  token_trimmed=$(echo "$QC_API_KEY" | tr -d '"')

  export _H1="Content-Type: application/json"
  export _H2="X-Auth-Email: $email_trimmed"
  export _H3="X-Auth-Key: $token_trimmed"

  if [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$QC_Api/$ep" "" "$m")"
  else
    response="$(_get "$QC_Api/$ep")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
