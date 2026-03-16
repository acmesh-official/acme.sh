#!/usr/bin/env sh

# shellcheck disable=SC2034
dns_bhosted_info='bHosted.nl DNS API
Site: bHosted.nl
Docs: Custom dnsapi plugin for acme.sh
Options:
  BHOSTED_Username        API username
  BHOSTED_Password        API password (MD5 hash zoals bHosted webservices voorbeeld)
  BHOSTED_TTL             TTL for TXT record (default: 300)
  BHOSTED_SLD             Optional override (handig voor multi-part TLDs zoals co.uk)
  BHOSTED_TLD             Optional override (handig voor multi-part TLDs zoals co.uk)
Notes:
  - Plugin gebruikt addrecord + delrecord voor DNS-01 challenge
  - Record ID wordt uit addrecord XML response gehaald en gecached voor cleanup
'

BHOSTED_API_ROOT="https://webservices.bhosted.com/dns"

############  Public functions #####################

# Usage: dns_bhosted_add _acme-challenge.www.example.com "txt-value"
dns_bhosted_add() {
  fulldomain="$1"
  txtvalue="$2"

  _debug "fulldomain" "$fulldomain"
  _debug "txtvalue" "$txtvalue"

  _bhosted_load_credentials || return 1
  _bhosted_get_root "$fulldomain" || return 1

  _info "Adding TXT record: ${_bhosted_name}.${_domain}"

  BHOSTED_TTL="${BHOSTED_TTL:-$(_readaccountconf_mutable BHOSTED_TTL)}"
  BHOSTED_TTL="${BHOSTED_TTL:-300}"
  _saveaccountconf_mutable BHOSTED_TTL "$BHOSTED_TTL"

  _bhosted_api_add_txt "$_bhosted_sld" "$_bhosted_tld" "$_bhosted_name" "$txtvalue" "$BHOSTED_TTL" || return 1

  # Extract and store record id for later cleanup
  _rec_id="$(_bhosted_extract_id "$response")"
  if [ -n "$_rec_id" ]; then
    _cache_key="$(_bhosted_cache_key "$fulldomain" "$txtvalue")"
    _debug "_cache_key" "$_cache_key"
    _debug "_rec_id" "$_rec_id"
    _saveaccountconf_mutable "$_cache_key" "$_rec_id"
  else
    _err "TXT record added but no record id found in response."
    _err "Cleanup may fail unless bHosted addrecord returns <id>...</id>."
    _debug2 "add response" "$response"
    return 1
  fi

  return 0
}

# Usage: dns_bhosted_rm _acme-challenge.www.example.com "txt-value"
dns_bhosted_rm() {
  fulldomain="$1"
  txtvalue="$2"

  _debug "fulldomain" "$fulldomain"
  _debug "txtvalue" "$txtvalue"

  _bhosted_load_credentials || return 1
  _bhosted_get_root "$fulldomain" || return 1

  _cache_key="$(_bhosted_cache_key "$fulldomain" "$txtvalue")"
  _rec_id="$(_readaccountconf_mutable "$_cache_key")"

  if [ -z "$_rec_id" ]; then
    _err "No cached bHosted record id found for cleanup."
    _err "Please delete TXT manually in bHosted DNS for: ${_bhosted_name}.${_domain}"
    return 1
  fi

  _info "Removing TXT record id=${_rec_id}: ${_bhosted_name}.${_domain}"
  _bhosted_api_del_record "$_bhosted_sld" "$_bhosted_tld" "$_rec_id" || return 1

  # Clear cached id after successful delete
  _saveaccountconf_mutable "$_cache_key" ""

  return 0
}

########  Private functions #####################

_bhosted_load_credentials() {
  BHOSTED_Username="${BHOSTED_Username:-$(_readaccountconf_mutable BHOSTED_Username)}"
  BHOSTED_Password="${BHOSTED_Password:-$(_readaccountconf_mutable BHOSTED_Password)}"

  if [ -z "$BHOSTED_Username" ] || [ -z "$BHOSTED_Password" ]; then
    BHOSTED_Username=""
    BHOSTED_Password=""
    _err "You didn't specify bHosted credentials."
    _err "Please export BHOSTED_Username and BHOSTED_Password (MD5 hash)."
    return 1
  fi

  _saveaccountconf_mutable BHOSTED_Username "$BHOSTED_Username"
  _saveaccountconf_mutable BHOSTED_Password "$BHOSTED_Password"

  return 0
}

# Determine root zone and host part
# Supports simple domains automatically (example.com, example.nl)
# For multi-part TLDs (example.co.uk), set:
#   BHOSTED_SLD=example
#   BHOSTED_TLD=co.uk
_bhosted_get_root() {
  domain="$1"

  BHOSTED_SLD="${BHOSTED_SLD:-$(_readaccountconf_mutable BHOSTED_SLD)}"
  BHOSTED_TLD="${BHOSTED_TLD:-$(_readaccountconf_mutable BHOSTED_TLD)}"

  if [ -n "$BHOSTED_SLD" ] && [ -n "$BHOSTED_TLD" ]; then
    _saveaccountconf_mutable BHOSTED_SLD "$BHOSTED_SLD"
    _saveaccountconf_mutable BHOSTED_TLD "$BHOSTED_TLD"

    _domain="${BHOSTED_SLD}.${BHOSTED_TLD}"
    case "$domain" in
    *."$_domain") ;;
    "$_domain") ;;
    *)
      _err "BHOSTED_SLD/BHOSTED_TLD do not match requested domain: $domain"
      return 1
      ;;
    esac

    _bhosted_sld="$BHOSTED_SLD"
    _bhosted_tld="$BHOSTED_TLD"
    _bhosted_name="${domain%."$_domain"}"
    if [ "$_bhosted_name" = "$domain" ]; then
      _bhosted_name=""
    fi

    [ -n "$_bhosted_name" ] || _bhosted_name="@"

    _debug "_domain" "$_domain"
    _debug "_bhosted_sld" "$_bhosted_sld"
    _debug "_bhosted_tld" "$_bhosted_tld"
    _debug "_bhosted_name" "$_bhosted_name"
    return 0
  fi

  # Auto-parse: assume last label = tld, label before = sld
  # Works for .nl / .com / .org etc.
  _bhosted_tld="$(printf "%s" "$domain" | awk -F. '{print $NF}')"
  _bhosted_sld="$(printf "%s" "$domain" | awk -F. '{print $(NF-1)}')"

  if [ -z "$_bhosted_sld" ] || [ -z "$_bhosted_tld" ]; then
    _err "Could not parse SLD/TLD from domain: $domain"
    return 1
  fi

  _domain="${_bhosted_sld}.${_bhosted_tld}"
  _bhosted_name="${domain%."$_domain"}"
  if [ "$_bhosted_name" = "$domain" ]; then
    _bhosted_name=""
  fi

  [ -n "$_bhosted_name" ] || _bhosted_name="@"

  _debug "_domain" "$_domain"
  _debug "_bhosted_sld" "$_bhosted_sld"
  _debug "_bhosted_tld" "$_bhosted_tld"
  _debug "_bhosted_name" "$_bhosted_name"

  return 0
}

_bhosted_api_add_txt() {
  _sld="$1"
  _tld="$2"
  _name="$3"
  _content="$4"
  _ttl="$5"

  _u_user="$(printf "%s" "$BHOSTED_Username" | _url_encode)"
  _u_pass="$(printf "%s" "$BHOSTED_Password" | _url_encode)"
  _u_sld="$(printf "%s" "$_sld" | _url_encode)"
  _u_tld="$(printf "%s" "$_tld" | _url_encode)"
  _u_name="$(printf "%s" "$_name" | _url_encode)"
  _u_content="$(printf "%s" "$_content" | _url_encode)"
  _u_ttl="$(printf "%s" "$_ttl" | _url_encode)"

  _url="${BHOSTED_API_ROOT}/addrecord?user=${_u_user}&password=${_u_pass}&tld=${_u_tld}&sld=${_u_sld}&type=TXT&name=${_u_name}&content=${_u_content}&ttl=${_u_ttl}"

  _debug "bHosted add endpoint" "${BHOSTED_API_ROOT}/addrecord"
  response="$(_get "$_url")"
  _ret="$?"

  _debug2 "bHosted add response" "$response"

  if [ "$_ret" != "0" ]; then
    _err "bHosted addrecord request failed"
    return 1
  fi

  if _bhosted_response_has_error "$response"; then
    _err "bHosted addrecord returned an error"
    _debug2 "response" "$response"
    return 1
  fi

  return 0
}

_bhosted_api_del_record() {
  _sld="$1"
  _tld="$2"
  _id="$3"

  _u_user="$(printf "%s" "$BHOSTED_Username" | _url_encode)"
  _u_pass="$(printf "%s" "$BHOSTED_Password" | _url_encode)"
  _u_sld="$(printf "%s" "$_sld" | _url_encode)"
  _u_tld="$(printf "%s" "$_tld" | _url_encode)"
  _u_id="$(printf "%s" "$_id" | _url_encode)"

  _url="${BHOSTED_API_ROOT}/delrecord?user=${_u_user}&password=${_u_pass}&tld=${_u_tld}&sld=${_u_sld}&id=${_u_id}"

  _debug "bHosted delete endpoint" "${BHOSTED_API_ROOT}/delrecord"
  response="$(_get "$_url")"
  _ret="$?"

  _debug2 "bHosted delete response" "$response"

  if [ "$_ret" != "0" ]; then
    _err "bHosted delrecord request failed"
    return 1
  fi

  if _bhosted_response_has_error "$response"; then
    _err "bHosted delrecord returned an error"
    _debug2 "response" "$response"
    return 1
  fi

  return 0
}

# Extract XML tag value from response, e.g. <id>12345</id>
_bhosted_xml_value() {
  _tag="$1"
  _resp="$2"

  # Flatten response to simplify parsing
  _flat="$(printf "%s" "$_resp" | tr -d '\r\n\t')"
  printf "%s" "$_flat" | sed -n "s:.*<${_tag}>\\([^<]*\\)</${_tag}>.*:\\1:p" | head -n 1
}

# Return code convention:
#   return 0 => response HAS error
#   return 1 => response has NO error (success)
_bhosted_response_has_error() {
  _resp="$1"

  # Empty response = error
  if [ -z "$_resp" ]; then
    _debug "Empty API response"
    return 0
  fi

  # Prefer explicit bHosted XML response fields
  if _contains "$_resp" "<response>"; then
    _errors="$(_bhosted_xml_value "errors" "$_resp")"
    _done="$(_bhosted_xml_value "done" "$_resp")"
    _subcommand="$(_bhosted_xml_value "subcommand" "$_resp")"
    _id="$(_bhosted_xml_value "id" "$_resp")"

    _debug "bHosted XML subcommand" "$_subcommand"
    _debug "bHosted XML id" "$_id"
    _debug "bHosted XML errors" "$_errors"
    _debug "bHosted XML done" "$_done"

    # Success according to provided format
    if [ "$_errors" = "0" ] && [ "$_done" = "true" ]; then
      return 1
    fi

    _debug "bHosted XML indicates failure"
    return 0
  fi

  # Fallback for unexpected/non-XML responses
  _resp_lc="$(printf "%s" "$_resp" | tr '[:upper:]' '[:lower:]')"

  if _contains "$_resp_lc" "error"; then
    _debug "Detected 'error' in response"
    return 0
  fi
  if _contains "$_resp_lc" "fout"; then
    _debug "Detected 'fout' in response"
    return 0
  fi
  if _contains "$_resp_lc" "invalid"; then
    _debug "Detected 'invalid' in response"
    return 0
  fi
  if _contains "$_resp_lc" "failed"; then
    _debug "Detected 'failed' in response"
    return 0
  fi
  if _contains "$_resp_lc" "denied"; then
    _debug "Detected 'denied' in response"
    return 0
  fi

  # If no explicit error markers found, assume success
  return 1
}

# Extract record id from response
# Supports bHosted XML first, then generic fallbacks
_bhosted_extract_id() {
  _resp="$1"

  # bHosted XML: <id>12345</id>
  _id="$(_bhosted_xml_value "id" "$_resp" | tr -cd '0-9')"
  if [ -n "$_id" ]; then
    printf "%s" "$_id"
    return 0
  fi

  # JSON: "id":12345
  _id="$(printf "%s" "$_resp" | _egrep_o '"id"[[:space:]]*:[[:space:]]*[0-9]+' | head -n 1 | tr -cd '0-9')"
  if [ -n "$_id" ]; then
    printf "%s" "$_id"
    return 0
  fi

  # key=value: id=12345
  _id="$(printf "%s" "$_resp" | _egrep_o '(^|[[:space:][:punct:]])id[[:space:]]*=[[:space:]]*[0-9]+' | head -n 1 | tr -cd '0-9')"
  if [ -n "$_id" ]; then
    printf "%s" "$_id"
    return 0
  fi

  # "record id 12345" / "recordid 12345"
  _id="$(printf "%s" "$_resp" | _egrep_o '(record[[:space:]]*id|recordid)[^0-9]*[0-9]+' | head -n 1 | tr -cd '0-9')"
  if [ -n "$_id" ]; then
    printf "%s" "$_id"
    return 0
  fi

  return 1
}

# Create a unique config key for cached record ids
_bhosted_cache_key() {
  _fd="$1"
  _tv="$2"
  # md5 hex of fulldomain|txtvalue to avoid invalid chars in conf key
  _hash="$(printf "%s|%s" "$_fd" "$_tv" | _digest md5 hex)"
  printf "BHOSTED_RECORD_ID_%s" "$_hash"
}
