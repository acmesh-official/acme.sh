#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_subreg_info='Subreg.cz
Site: subreg.cz
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_subreg
Options:
 SUBREG_API_USERNAME API username
 SUBREG_API_PASSWORD API password
Issues: github.com/acmesh-official/acme.sh/issues/6835
Author: Tomas Pavlic <https://github.com/tomaspavlic>
'

# Subreg SOAP API
# https://subreg.cz/manual/

SUBREG_API_URL="https://soap.subreg.cz/cmd.php"

########  Public functions #####################

# Usage: dns_subreg_add _acme-challenge.www.domain.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_subreg_add() {
  fulldomain=$1
  txtvalue=$2

  SUBREG_API_USERNAME="${SUBREG_API_USERNAME:-$(_readaccountconf_mutable SUBREG_API_USERNAME)}"
  SUBREG_API_PASSWORD="${SUBREG_API_PASSWORD:-$(_readaccountconf_mutable SUBREG_API_PASSWORD)}"
  if [ -z "$SUBREG_API_USERNAME" ] || [ -z "$SUBREG_API_PASSWORD" ]; then
    _err "SUBREG_API_USERNAME and SUBREG_API_PASSWORD are not set."
    return 1
  fi

  _saveaccountconf_mutable SUBREG_API_USERNAME "$SUBREG_API_USERNAME"
  _saveaccountconf_mutable SUBREG_API_PASSWORD "$SUBREG_API_PASSWORD"

  if ! _subreg_login; then
    return 1
  fi

  if ! _get_root "$fulldomain"; then
    _err "Cannot determine root domain for: $fulldomain"
    return 1
  fi

  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _subreg_soap "Add_DNS_Record" "<domain>$_domain</domain><record><name>$_sub_domain</name><type>TXT</type><content>$txtvalue</content><prio>0</prio><ttl>120</ttl></record>"
  if _subreg_ok; then
    _record_id="$(_subreg_map_get record_id)"

    if [ -z "$_record_id" ]; then
      _err "Subreg API did not return a record_id for TXT record on $fulldomain"
      _err "$response"
      return 1
    fi

    _savedomainconf "$(_subreg_record_id_key "$txtvalue")" "$_record_id"
    return 0
  fi
  _err "Failed to add TXT record."
  _err "$response"
  return 1
}

# Usage: dns_subreg_rm _acme-challenge.www.domain.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_subreg_rm() {
  fulldomain=$1
  txtvalue=$2

  SUBREG_API_USERNAME="${SUBREG_API_USERNAME:-$(_readaccountconf_mutable SUBREG_API_USERNAME)}"
  SUBREG_API_PASSWORD="${SUBREG_API_PASSWORD:-$(_readaccountconf_mutable SUBREG_API_PASSWORD)}"
  if [ -z "$SUBREG_API_USERNAME" ] || [ -z "$SUBREG_API_PASSWORD" ]; then
    _err "SUBREG_API_USERNAME and SUBREG_API_PASSWORD are not set."
    return 1
  fi

  if ! _subreg_login; then
    return 1
  fi

  if ! _get_root "$fulldomain"; then
    _err "Cannot determine root domain for: $fulldomain"
    return 1
  fi

  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _record_id="$(_readdomainconf "$(_subreg_record_id_key "$txtvalue")")"
  if [ -z "$_record_id" ]; then
    _err "Could not find saved record ID for $fulldomain"
    return 1
  fi

  _debug "Deleting record ID: $_record_id"
  _subreg_soap "Delete_DNS_Record" "<domain>$_domain</domain><record><id>$_record_id</id></record>"
  if _subreg_ok; then

    _cleardomainconf "$(_subreg_record_id_key "$txtvalue")"
    return 0
  fi

  _err "Failed to delete TXT record."
  _err "$response"
  return 1
}

####################  Private functions #####################

# Build a domain-conf key for storing the record ID of a given TXT value.
# Base64url chars include '-' which is invalid in shell variable names, so replace with '_'.
_subreg_record_id_key() {
  printf 'SUBREG_RECORD_ID_%s' "$(printf '%s' "$1" | tr '-' '_')"
}

# Check if the current $response contains a successful status in the ns2:Map format:
# <item><key ...>status</key><value ...>ok</value></item>
_subreg_ok() {
  [ "$(_subreg_map_get status)" = "ok" ]
}

# Extract the value for a given key from the ns2:Map response.
# Usage: _subreg_map_get keyname
# Reads from $response
_subreg_map_get() {
  _key="$1"
  echo "$response" | tr -d '\n\r' | _egrep_o ">${_key}</key><value[^>]*>[^<]*</value>" | sed 's/.*<value[^>]*>//;s/<\/value>//'
}

# Login and store session token in _subreg_ssid
_subreg_login() {
  _debug "Logging in to Subreg API as $SUBREG_API_USERNAME"
  _subreg_soap_noauth "Login" "<login>$SUBREG_API_USERNAME</login><password>$SUBREG_API_PASSWORD</password>"
  if ! _subreg_ok; then
    _err "Subreg login failed."
    _err "$response"
    return 1
  fi
  _subreg_ssid="$(_subreg_map_get ssid)"
  if [ -z "$_subreg_ssid" ]; then
    _err "Subreg login: could not extract session token (ssid)."
    return 1
  fi
  _debug "Subreg login: session token (ssid) obtained"
  return 0
}

# _get_root _acme-challenge.www.domain.com
# returns _sub_domain and _domain
_get_root() {
  domain=$1
  i=1
  p=1

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    if [ -z "$h" ]; then
      _err "Unable to retrieve DNS zone matching domain: $domain"
      return 1
    fi

    _subreg_soap "Get_DNS_Zone" "<domain>$h</domain>"

    if _subreg_ok; then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-"$p")
      _domain="$h"
      return 0
    fi

    p=$i
    i=$(_math "$i" + 1)
  done
}

# Send a SOAP request without authentication (used for Login)
# _subreg_soap_noauth command inner_xml
_subreg_build_soap() {
  _cmd="$1"
  _data_inner="$2"

  _soap_body="<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<SOAP-ENV:Envelope
    xmlns:SOAP-ENV=\"http://schemas.xmlsoap.org/soap/envelope/\"
    xmlns:ns1=\"http://soap.subreg.cz/soap\"
    xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\"
    xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"
    xmlns:SOAP-ENC=\"http://schemas.xmlsoap.org/soap/encoding/\"
    SOAP-ENV:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\">
  <SOAP-ENV:Body>
    <ns1:${_cmd}>
      <data>
        ${_data_inner}
      </data>
    </ns1:${_cmd}>
  </SOAP-ENV:Body>
</SOAP-ENV:Envelope>"

  export _H1="Content-Type: text/xml"
  export _H2="SOAPAction: http://soap.subreg.cz/soap#${_cmd}"
  response="$(_post "$_soap_body" "$SUBREG_API_URL" "" "POST" "text/xml")"
}

# Send an authenticated SOAP request (requires _subreg_ssid to be set)
# _subreg_soap command inner_xml
_subreg_soap_noauth() {
  _cmd="$1"
  _inner="$2"

  _subreg_build_soap "$_cmd" "$_inner"
}

# Send an authenticated SOAP request (requires _subreg_ssid to be set)
# _subreg_soap command inner_xml
_subreg_soap() {
  _cmd="$1"
  _inner="$2"
  _inner_with_ssid="<ssid>${_subreg_ssid}</ssid>${_inner}"

  _subreg_build_soap "$_cmd" "$_inner_with_ssid"
}
