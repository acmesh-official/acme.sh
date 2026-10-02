#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_jd_info='jdcloud.com
Site: jdcloud.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_jd
Options:
 JD_ACCESS_KEY_ID Access key ID
 JD_ACCESS_KEY_SECRET Access key secret
 JD_REGION Region. E.g. "cn-north-1"
Issues: github.com/acmesh-official/acme.sh/issues/7202
Author: @skysaint
'

_JD_ACCOUNT="https://uc.jdcloud.com/account/accesskey"

_JD_PROD="domainservice"
_JD_API="jdcloud-api.com"

_JD_API_VERSION="v2"
_JD_DEFAULT_REGION="cn-north-1"

_JD_HOST="$_JD_PROD.$_JD_API"

########  Public functions #####################

#Usage: dns_jd_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_jd_add() {
  fulldomain=$1
  txtvalue=$2

  JD_ACCESS_KEY_ID="${JD_ACCESS_KEY_ID:-$(_readaccountconf_mutable JD_ACCESS_KEY_ID)}"
  JD_ACCESS_KEY_SECRET="${JD_ACCESS_KEY_SECRET:-$(_readaccountconf_mutable JD_ACCESS_KEY_SECRET)}"
  JD_REGION="${JD_REGION:-$(_readaccountconf_mutable JD_REGION)}"

  if [ -z "$JD_ACCESS_KEY_ID" ] || [ -z "$JD_ACCESS_KEY_SECRET" ]; then
    JD_ACCESS_KEY_ID=""
    JD_ACCESS_KEY_SECRET=""
    _err "You haven't specifed the jdcloud api key id or api key secret yet."
    _err "Please create your key and try again. see $(__green $_JD_ACCOUNT)"
    return 1
  fi

  _saveaccountconf_mutable JD_ACCESS_KEY_ID "$JD_ACCESS_KEY_ID"
  _saveaccountconf_mutable JD_ACCESS_KEY_SECRET "$JD_ACCESS_KEY_SECRET"
  if [ -z "$JD_REGION" ]; then
    _debug "Using default region: $_JD_DEFAULT_REGION"
    JD_REGION="$_JD_DEFAULT_REGION"
  else
    _saveaccountconf_mutable JD_REGION "$JD_REGION"
  fi
  _JD_BASE_URI="$_JD_API_VERSION/regions/$JD_REGION"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  #_debug "Getting describeViewTree"

  _debug "Adding records"

  _addrr="{\"req\":{\"hostRecord\":\"$_sub_domain\",\"hostValue\":\"$txtvalue\",\"ttl\":300,\"type\":\"TXT\",\"viewValue\":-1}}"
  #_addrr='{"req":{"hostRecord":"_acme-challenge","hostValue":"XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs","ttl":300,"type":"TXT","viewValue":-1}}'
  if jd_rest POST "domain/$_domain_id/ResourceRecord" "" "$_addrr"; then
    _info "TXT record added successfully."
    return 0
  fi

  return 1
}

dns_jd_rm() {
  fulldomain=$1
  txtvalue=$2

  JD_ACCESS_KEY_ID="${JD_ACCESS_KEY_ID:-$(_readaccountconf_mutable JD_ACCESS_KEY_ID)}"
  JD_ACCESS_KEY_SECRET="${JD_ACCESS_KEY_SECRET:-$(_readaccountconf_mutable JD_ACCESS_KEY_SECRET)}"
  JD_REGION="${JD_REGION:-$(_readaccountconf_mutable JD_REGION)}"

  if [ -z "$JD_REGION" ]; then
    _debug "Using default region: $_JD_DEFAULT_REGION"
    JD_REGION="$_JD_DEFAULT_REGION"
  fi

  _JD_BASE_URI="$_JD_API_VERSION/regions/$JD_REGION"

  _info "Removing TXT record for $fulldomain"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  # List records, filter by hostRecord and use a large pageSize so it isn't missed on record-heavy zones.
  if ! jd_rest GET "domain/$_domain_id/ResourceRecord" "pageSize=50&search=$_sub_domain"; then
    _err "Failed to list resource records"
    return 1
  fi

  # Match record by hostRecord + type TXT + hostValue
  _record_id=""
  _matched="$(echo "$response" | tr '{' '\n' | grep "\"hostRecord\":\"$_sub_domain\"" | grep "\"type\":\"TXT\"" | grep "\"hostValue\":\"$txtvalue\"")"
  _debug2 _matched "$_matched"

  if [ -z "$_matched" ]; then
    _info "TXT record not found, nothing to remove."
    return 0
  fi

  _record_id="$(echo "$_matched" | tr ',' '\n' | grep "\"id\":" | cut -d : -f 2 | tr -d '"' | _head_n 1)"
  _debug _record_id "$_record_id"

  if [ -z "$_record_id" ]; then
    _info "Could not extract record id from response, nothing to remove."
    return 0
  fi

  if jd_rest DELETE "domain/$_domain_id/ResourceRecord/$_record_id"; then
    _info "TXT record deleted successfully."
    return 0
  fi

  _err "Failed to delete TXT record."
  return 1
}

####################  Private functions below ##################################

_get_root() {
  domain=$1
  i=1
  p=1

  if ! jd_rest GET "domain"; then
    _err "error get domain list"
    return 1
  fi

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    _debug2 "Checking domain: $h"
    if [ -z "$h" ]; then
      #not valid
      _err "Invalid domain"
      return 1
    fi

    if _contains "$response" "\"domainName\":\"$h\""; then
      hostedzone="$(echo "$response" | tr '{}' '\n' | grep "\"domainName\":\"$h\"")"
      _debug hostedzone "$hostedzone"
      if [ "$hostedzone" ]; then
        _domain_id="$(echo "$hostedzone" | tr ',' '\n' | grep "\"id\":" | cut -d : -f 2)"
        if [ "$_domain_id" ]; then
          _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-"$p")
          _domain=$h
          return 0
        fi
      fi
      _err "Can't find domain with id: $h"
      return 1
    fi
    p=$i
    i=$(_math "$i" + 1)
  done

  return 1
}

# Use '%b' with printf to expand \n escapes in CanonicalRequest and StringToSign.
# Use '%s' for plain values that contain no escapes to avoid unintended expansion.
#method uri qstr data
jd_rest() {
  mtd="$1"
  ep="$2"
  qsr="$3"
  data="$4"

  _debug mtd "$mtd"
  _debug ep "$ep"
  _debug qsr "$qsr"
  _debug data "$data"

  CanonicalURI="/$_JD_BASE_URI/$ep"
  _debug2 CanonicalURI "$CanonicalURI"

  CanonicalQueryString="$qsr"
  _debug2 CanonicalQueryString "$CanonicalQueryString"

  RequestDate="$(date -u +"%Y%m%dT%H%M%SZ")"
  #RequestDate="20190713T082155Z" ######################################################
  _debug2 RequestDate "$RequestDate"
  export _H1="X-Jdcloud-Date: $RequestDate"

  RequestNonce="2bd0852a-8bae-4087-b2d5-$(_time)"
  #RequestNonce="894baff5-72d4-4244-883a-7b2eb51e7fbe" #################################
  _debug2 RequestNonce "$RequestNonce"
  export _H2="X-Jdcloud-Nonce: $RequestNonce"

  if [ "$data" ]; then
    CanonicalHeaders="content-type:application/json\n"
    SignedHeaders="content-type;"
  else
    CanonicalHeaders=""
    SignedHeaders=""
  fi
  CanonicalHeaders="${CanonicalHeaders}host:$_JD_HOST\nx-jdcloud-date:$RequestDate\nx-jdcloud-nonce:$RequestNonce\n"
  SignedHeaders="${SignedHeaders}host;x-jdcloud-date;x-jdcloud-nonce"

  _debug2 CanonicalHeaders "$CanonicalHeaders"
  _debug2 SignedHeaders "$SignedHeaders"

  Hash="sha256"

  RequestPayload="$data"
  _debug2 RequestPayload "$RequestPayload"

  RequestPayloadHash="$(printf "%s" "$RequestPayload" | _digest "$Hash" hex | _lower_case)"
  _debug2 RequestPayloadHash "$RequestPayloadHash"

  CanonicalRequest="$mtd\n$CanonicalURI\n$CanonicalQueryString\n$CanonicalHeaders\n$SignedHeaders\n$RequestPayloadHash"
  _debug2 CanonicalRequest "$CanonicalRequest"

  HashedCanonicalRequest="$(printf '%b' "$CanonicalRequest" | _digest "$Hash" hex)"
  _debug2 HashedCanonicalRequest "$HashedCanonicalRequest"

  Algorithm="JDCLOUD2-HMAC-SHA256"
  _debug2 Algorithm "$Algorithm"

  RequestDateOnly="$(echo "$RequestDate" | cut -c 1-8)"
  _debug2 RequestDateOnly "$RequestDateOnly"

  Region="$JD_REGION"
  Service="$_JD_PROD"

  CredentialScope="$RequestDateOnly/$Region/$Service/jdcloud2_request"
  _debug2 CredentialScope "$CredentialScope"

  StringToSign="$Algorithm\n$RequestDate\n$CredentialScope\n$HashedCanonicalRequest"

  _debug2 StringToSign "$StringToSign"

  kSecret="JDCLOUD2$JD_ACCESS_KEY_SECRET"

  _secure_debug2 kSecret "$kSecret"

  kSecretH="$(printf "%s" "$kSecret" | _hex_dump | tr -d " ")"
  _secure_debug2 kSecretH "$kSecretH"

  kDateH="$(printf '%s' "$RequestDateOnly" | _hmac "$Hash" "$kSecretH" hex)"
  _debug2 kDateH "$kDateH"

  kRegionH="$(printf '%s' "$Region" | _hmac "$Hash" "$kDateH" hex)"
  _debug2 kRegionH "$kRegionH"

  kServiceH="$(printf '%s' "$Service" | _hmac "$Hash" "$kRegionH" hex)"
  _debug2 kServiceH "$kServiceH"

  kSigningH="$(printf '%s' "jdcloud2_request" | _hmac "$Hash" "$kServiceH" hex)"
  _debug2 kSigningH "$kSigningH"

  signature="$(printf '%b' "$StringToSign" | _hmac "$Hash" "$kSigningH" hex)"
  _debug2 signature "$signature"

  Authorization="$Algorithm Credential=$JD_ACCESS_KEY_ID/$CredentialScope, SignedHeaders=$SignedHeaders, Signature=$signature"
  _debug2 Authorization "$Authorization"

  _H3="Authorization: $Authorization"
  _debug _H3 "$_H3"

  url="https://$_JD_HOST$CanonicalURI"
  if [ "$qsr" ]; then
    url="https://$_JD_HOST$CanonicalURI?$qsr"
  fi

  if [ "$mtd" = "GET" ]; then
    response="$(_get "$url")"
  else
    response="$(_post "$data" "$url" "" "$mtd" "application/json")"
  fi

  _ret="$?"
  _debug2 response "$response"
  if [ "$_ret" = "0" ]; then
    if _contains "$response" "\"error\""; then
      _err "Response error:$response"
      return 1
    fi
  fi

  return "$_ret"
}
