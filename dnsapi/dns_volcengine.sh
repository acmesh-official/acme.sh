#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_volcengine_info='Volcengine DNS API
Site: https://www.volcengine.com/docs/6758/155086
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_volcengine
Options:
 Volcengine_ACCESS_KEY_ID API Key ID
 Volcengine_SECRET_ACCESS_KEY API Secret
'

Volcengine_HOST="dns.volcengineapi.com"
Volcengine_URL="https://$Volcengine_HOST"

########  Public functions #####################

#Usage: dns_volcengine_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_volcengine_add() {
  fulldomain=$1
  txtvalue=$2

  Volcengine_ACCESS_KEY_ID="${Volcengine_ACCESS_KEY_ID:-$(_readaccountconf_mutable Volcengine_ACCESS_KEY_ID)}"
  Volcengine_SECRET_ACCESS_KEY="${Volcengine_SECRET_ACCESS_KEY:-$(_readaccountconf_mutable Volcengine_SECRET_ACCESS_KEY)}"

  if [ -z "$Volcengine_ACCESS_KEY_ID" ] || [ -z "$Volcengine_SECRET_ACCESS_KEY" ]; then
    Volcengine_ACCESS_KEY_ID=""
    Volcengine_SECRET_ACCESS_KEY=""
    _err "You haven't specified the volcengine dns api key id and and api key secret yet."
    return 1
  fi

  #save the api key and email to the account conf file.
  _saveaccountconf_mutable Volcengine_ACCESS_KEY_ID "$Volcengine_ACCESS_KEY_ID"
  _saveaccountconf_mutable Volcengine_SECRET_ACCESS_KEY "$Volcengine_SECRET_ACCESS_KEY"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    _sleep 1
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  # _info "Getting existing records for $fulldomain"
  if ! volcengine_rest POST "" "Action=ListRecords&Version=2018-08-01" "{\"ZID\":$_domain_id,\"Host\":\"$_sub_domain\",\"Type\":\"TXT\",\"Value\":\"$txtvalue\",\"SearchMode\":\"exact\"}"; then
    _sleep 1
    return 1
  fi

  if _contains "$response" "\"FQDN\":\"$_domain\""; then
    _record_id="$(echo "$response" | _egrep_o "\"RecordID\":\"[0-9]+\"," | cut -d: -f2 | cut -d, -f1 | tr -d '"')"
    _debug "_record_id" "$_record_id"
  else
    _debug "single new add"
  fi

  if [ "$_record_id" ] && _contains "$response" "$txtvalue"; then
    _info "The TXT record already exists. Skipping."
    _sleep 1
    return 0
  fi

  _debug "Adding records"

  if volcengine_rest POST "" "Action=CreateRecord&Version=2018-08-01" "{\"ZID\":$_domain_id,\"Host\":\"$_sub_domain\",\"Type\":\"TXT\",\"Value\":\"$txtvalue\"}"; then
    _info "TXT record updated successfully."
    _sleep 1
    return 0
  fi

  _sleep 1
  return 1
}

#fulldomain txtvalue
dns_volcengine_rm() {
  fulldomain=$1
  txtvalue=$2

  Volcengine_ACCESS_KEY_ID="${Volcengine_ACCESS_KEY_ID:-$(_readaccountconf_mutable Volcengine_ACCESS_KEY_ID)}"
  Volcengine_SECRET_ACCESS_KEY="${Volcengine_SECRET_ACCESS_KEY:-$(_readaccountconf_mutable Volcengine_SECRET_ACCESS_KEY)}"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    _sleep 1
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _info "Getting existing records for $fulldomain"

  if ! volcengine_rest POST "" "Action=ListRecords&Version=2018-08-01" "{\"ZID\":$_domain_id,\"Host\":\"$_sub_domain\",\"Type\":\"TXT\",\"Value\":\"$txtvalue\",\"SearchMode\":\"exact\"}"; then
    _sleep 1
    return 1
  fi

  if _contains "$response" "\"FQDN\":\"$_domain\""; then
    _record_id="$(echo "$response" | _egrep_o "\"RecordID\":\"[0-9]+\"," | cut -d: -f2 | cut -d, -f1 | tr -d '"')"
    _debug "_record_id" "$_record_id"
  else
    _debug "no records exist, skip"
    _sleep 1
    return 0
  fi

  if volcengine_rest POST "" "Action=DeleteRecord&Version=2018-08-01" "{\"RecordID\":\"$_record_id\"}"; then
    _info "TXT record deleted successfully."
    _sleep 1
    return 0
  fi
  _sleep 1
  return 1
}

####################  Private functions below ##################################

_get_root() {
  domain=$1
  i=1
  p=1

  # iterate over names (a.b.c.d -> b.c.d -> c.d -> d)
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    _debug "Checking domain: $h"
    if [ -z "$h" ]; then
      _err "invalid domain"
      return 1
    fi

    # iterate over paginated result for list_hosted_zones
    volcengine_rest POST "" "Action=ListZones&Version=2018-08-01" "{\"Key\":\"$h\",\"SearchMode\":\"exact\"}"
    if _contains "$response" "\"ZoneName\":\"$h\""; then
      _domain_id=$(printf "%s" "$response" | _egrep_o "\"ZID\":[0-9]+," | cut -d: -f2 | cut -d, -f1)
      if [ "$_domain_id" ]; then
        _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-"$p")
        _domain=$h
        return 0
      fi
      _err "Can't find domain with id: $h"
      return 1
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

#method uri qstr data
volcengine_rest() {
  mtd="$1"
  ep="$2"
  qsr="$3"
  data="$4"

  _debug mtd "$mtd"
  _debug ep "$ep"
  _debug qsr "$qsr"
  _debug data "$data"

  CanonicalURI="/$ep"
  _debug2 CanonicalURI "$CanonicalURI"

  CanonicalQueryString="$qsr"
  _debug2 CanonicalQueryString "$CanonicalQueryString"

  RequestDate="$(date -u +"%Y%m%dT%H%M%SZ")"
  _debug2 RequestDate "$RequestDate"

  #RequestDate="20161120T141056Z" ##############

  Hash="sha256"

  _H1="X-Date: $RequestDate"
  _debug2 _H1 "$_H1"

  volcengine_host="$Volcengine_HOST"
  CanonicalHeaders="host:$volcengine_host\n"
  SignedHeaders="host"

  if [ -n "$data" ]; then
    XContentSha256="$(printf "%s" "$data" | _digest "$Hash" hex)"
    _H4="x-content-sha256: $XContentSha256"
    _debug2 _H4 "$_H4"

    CanonicalHeaders="${CanonicalHeaders}x-content-sha256:$XContentSha256\n"
    SignedHeaders="${SignedHeaders};x-content-sha256"
  fi

  CanonicalHeaders="${CanonicalHeaders}x-date:$RequestDate\n"
  SignedHeaders="${SignedHeaders};x-date"

  if [ -n "$Volcengine_SESSION_TOKEN" ]; then
    _H3="x-security-token: $Volcengine_SESSION_TOKEN"
    CanonicalHeaders="${CanonicalHeaders}x-security-token:$Volcengine_SESSION_TOKEN\n"
    SignedHeaders="${SignedHeaders};x-security-token"
  fi

  _debug2 CanonicalHeaders "$CanonicalHeaders"
  _debug2 SignedHeaders "$SignedHeaders"

  RequestPayload="$data"
  _debug2 RequestPayload "$RequestPayload"

  CanonicalRequest="$mtd\n$CanonicalURI\n$CanonicalQueryString\n$CanonicalHeaders\n$SignedHeaders\n$(printf "%s" "$RequestPayload" | _digest "$Hash" hex)"
  _debug2 CanonicalRequest "$CanonicalRequest"

  HashedCanonicalRequest="$(printf "$CanonicalRequest%s" | _digest "$Hash" hex)"
  _debug2 HashedCanonicalRequest "$HashedCanonicalRequest"

  Algorithm="HMAC-SHA256"
  _debug2 Algorithm "$Algorithm"

  RequestDateOnly="$(echo "$RequestDate" | cut -c 1-8)"
  _debug2 RequestDateOnly "$RequestDateOnly"

  Region="cn-beijing"
  Service="dns"

  CredentialScope="$RequestDateOnly/$Region/$Service/request"
  _debug2 CredentialScope "$CredentialScope"

  StringToSign="$Algorithm\n$RequestDate\n$CredentialScope\n$HashedCanonicalRequest"

  _debug2 StringToSign "$StringToSign"

  kSecret="$Volcengine_SECRET_ACCESS_KEY"

  #kSecret="wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY" ############################

  _secure_debug2 kSecret "$kSecret"

  kSecretH="$(printf "%s" "$kSecret" | _hex_dump | tr -d " ")"
  _secure_debug2 kSecretH "$kSecretH"

  kDateH="$(printf "$RequestDateOnly%s" | _hmac "$Hash" "$kSecretH" hex)"
  _debug2 kDateH "$kDateH"

  kRegionH="$(printf "$Region%s" | _hmac "$Hash" "$kDateH" hex)"
  _debug2 kRegionH "$kRegionH"

  kServiceH="$(printf "$Service%s" | _hmac "$Hash" "$kRegionH" hex)"
  _debug2 kServiceH "$kServiceH"

  kSigningH="$(printf "%s" "request" | _hmac "$Hash" "$kServiceH" hex)"
  _debug2 kSigningH "$kSigningH"

  signature="$(printf "$StringToSign%s" | _hmac "$Hash" "$kSigningH" hex)"
  _debug2 signature "$signature"

  Authorization="$Algorithm Credential=$Volcengine_ACCESS_KEY_ID/$CredentialScope, SignedHeaders=$SignedHeaders, Signature=$signature"
  _debug2 Authorization "$Authorization"

  _H2="Authorization: $Authorization"
  _debug _H2 "$_H2"

  url="$Volcengine_URL/$ep"
  if [ "$qsr" ]; then
    url="$Volcengine_URL/$ep?$qsr"
  fi

  if [ "$mtd" = "GET" ]; then
    response="$(_get "$url")"
  else
    response="$(_post "$data" "$url" "" "POST" "application/json")"
  fi

  _ret="$?"
  _debug2 response "$response"
  if [ "$_ret" = "0" ]; then
    if _contains "$response" "\"Error\":{"; then
      _err "Response error:$response"
      return 1
    fi
  fi

  return "$_ret"
}
