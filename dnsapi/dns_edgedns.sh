#!/usr/bin/env sh

# Akamai Edge DNS v2  API
# User must provide Open Edgegrid API credentials to the EdgeDNS installation. The remote user in EdgeDNS must have CRUD access to
# Edge DNS Zones and Recordsets, e.g. DNS—Zone Record Management authorization

# Report bugs to https://control.akamai.com/apps/support-ui/#/contact-support

# Values to export:
# --EITHER--  
# *** NOT IMPLEMENTED YET ***
# specify Edgegrid credentials file and section
# AKAMAI_EDGERC=<full file path> 
# AKAMAI_EDGERC_SECTION="default"
## --OR--
# specify indiviual credentials
# export AKAMAI_HOST = <host>
# export AKAMAI_ACCESS_TOKEN = <access token> 
# export AKAMAI_CLIENT_TOKEN = <client token>
# export AKAMAI_CLIENT_SECRET = <client secret>

ACME_EDGEDNS_VERSION="0.1.0"

########  Public functions #####################

# Usage: dns_edgedns_add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
# Used to add txt record
#
dns_edgedns_add() {
  fulldomain=$1
  txtvalue=$2

  _debug "ENTERING DNS_EDGEDNS_ADD"

  _debug2 "fulldomain" "$fulldomain"
  _debug2 "txtvalue" "$txtvalue"
 
  if ! _EDGEDNS_credentials; then
    _err "$@"
    return 1
  fi

  if ! _EDGEDNS_getZoneInfo "$fulldomain"; then
    _err "Invalid domain"
    return 1
  fi
  _debug2 "Add: zone" "${zone}"
  acmeRecordURI=$(printf "%s/%s/names/%s/type/TXT" "${edge_endpoint}" "${zone}" "${fulldomain}") 
  _debug3 "Add URL" "$acmeRecordURI"
  # Get existing TXT record
  _edge_result=$(_edgedns_rest GET "$acmeRecordURI")
  _api_status="$?"
  if [ "$_api_status" -ne 0 ] && [ "$_edge_result" != "404" ]; then
    _err "$(printf "Failure accessing Akamai Edge DNS API Server. Error: %s" "$_edge_result")"
    return 1
  fi
  rdata="\"$txtvalue\""
  record_op="POST"
  if [ "$_api_status" -eq 0 ]; then
    # record already exists. Get existing record data and update
    record_op="PUT"
    rdlist=$(echo -n "$response" | _egrep_o "\"rdata\"\\s*:\\s*\\[\\s*\"[^\"]*\"\\s*]" | cut -d : -f 2 | tr -d "[]\"")  
    _debug2 "existing TXT found"
    _debug2 "record data" "$rdlist"
    # value already there?
    if _contains "$rdlist" "$txtvalue" ; then
      return 0
    fi
    comma=","
    rdata="$rdata$comma\"${txtvalue}\""
  fi
  _debug2 "new/updated rdata: " "${rdata}"
  # Add the txtvalue TXT Record
  body="{\"name\":\"$fulldomain\",\"type\":\"TXT\",\"ttl\":600, \"rdata\":"[${rdata}]"}"
  _debug3 "Add body '${body}'"
  _edge_result=$(_edgedns_rest "$record_op" "$acmeRecordURI" "$body")
  _api_status="$?"
  if [ "$_api_status" -eq 0 ]; then
    _log "$(printf "Text value %s added to recordset %s" "${txtvalue}" "${fulldomain}")"
    return 0
  else
    _err "$(printf "error adding TXT record for validation. Error: %s" "$_edge_result")"
    return 1
  fi
}

# Usage: dns_edgedns_rm   _acme-challenge.www.domain.com
# Used to delete txt record
#
dns_edgedns_rm() {
  fulldomain=$1
}

####################  Private functions below ##################################

_EDGEDNS_credentials() {
  _debug "GettingEdge DNS credentials" 
  _log $(printf "ACME DNSAPI Edge DNS version %s" ${ACME_EDGEDNS_VERSION})
  args_missing=0
  if [ -z "${AKAMAI_ACCESS_TOKEN}" ]; then
    AKAMAI_ACCESS_TOKEN=""
    AKAMAI_CLIENT_TOKEN=""
    AKAMAI_HOST=""
    AKAMAI_CLIENT_SECRET=""
    _err "AKAMAI_ACCESS_TOKEN is missing"
    args_missing=1
  fi
  if [ -z "$AKAMAI_CLIENT_TOKEN" ]; then
    AKAMAI_ACCESS_TOKEN=""
    AKAMAI_CLIENT_TOKEN=""
    AKAMAI_HOST=""
    AKAMAI_CLIENT_SECRET=""
    _err "AKAMAI_CLIENT_TOKEN is missing"
    args_missing=1
  fi
  if [ -z "${AKAMAI_HOST}" ]; then
    AKAMAI_ACCESS_TOKEN=""
    AKAMAI_CLIENT_TOKEN=""
    AKAMAI_HOST=""
    AKAMAI_CLIENT_SECRET=""
    _err "AKAMAI_HOST is missing"
    args_missing=1
  fi
  if [ -z "${AKAMAI_CLIENT_SECRET}" ]; then
    AKAMAI_ACCESS_TOKEN=""
    AKAMAI_CLIENT_TOKEN=""
    AKAMAI_HOST=""
    AKAMAI_CLIENT_SECRET=""
    _err "AKAMAI_CLIENT_SECRET is missing"
    args_missing=1
  fi

  if [ "${args_missing}" = 1 ]; then
    _err "You have not properly specified the EdgeDNS Open Edgegrid API credentials. Please try again."
    return 1
  else
    _saveaccountconf_mutable AKAMAI_ACCESS_TOKEN "${AKAMAI_ACCESS_TOKEN}"
    _saveaccountconf_mutable AKAMAI_CLIENT_TOKEN "${AKAMAI_CLIENT_TOKEN}"
    _saveaccountconf_mutable AKAMAI_HOST "${AKAMAI_HOST}"
    _saveaccountconf_mutable AKAMAI_CLIENT_SECRET "${AKAMAI_CLIENT_SECRET}"
    # Set whether curl should use secure or insecure mode
  fi
  export HTTPS_INSECURE=0     # All Edgegrid API calls are secure
  edge_endpoint=$(printf "https://%s/config-dns/v2/zones" "${AKAMAI_HOST}")
  _debug3 "Edge API Endpoint:" "${edge_endpoint}"

}

_EDGEDNS_getZoneInfo() {
  _debug "Getting Zoneinfo"
  zoneEnd=false
  curZone=$1
  while [ -n "${zoneEnd}" ]; do
    # we can strip the first part of the fulldomain, since its just the _acme-challenge string
    curZone="${curZone#*.}"
    # suffix . needed for zone -> domain.tld.
    # create zone get url
    get_zone_url=$(printf "%s/%s" "${edge_endpoint}" "${curZone}")
    _debug3 "Zone Get: " "${get_zone_url}"
    curResult=$(_edgedns_rest GET "$get_zone_url")
    retVal=$?
    if [ $retVal -ne 0 ]; then
      if ["$curResult" != "404" ]; then
        _err "$(printf "Managed zone validation failed. Error response: %s" "$retVal")"
        return 1
      fi
    fi

    if _contains "${curResult}" "\"zone\":" ; then
      _debug2 "Zone data" "${curResult}"
      zone=$(echo -n "${curResult}" | _egrep_o "\"zone\"\\s*:\\s*\"[^\"]*\"" | _head_n 1 | cut -d : -f 2 | tr -d "\"")
      _debug2 "Zone" "${zone}"
      zoneFound=""
      zoneEnd=""
      return 0
    fi

    if [ "${curZone#*.}" != "$curZone" ]; then
      _debug2 $(printf "%s still contains a '.' - so we can check next higher level" "$curZone")
    else
      zoneEnd=true
      _err "Couldn't retrieve zone data."
      return 1
    fi
  done
  _err "Failed to  retrieve zone data."
  return 2
}

_edgedns_headers=""

_edgedns_rest() {
  _debug "Handling API Request"
  m=$1
  # Assume endpoint is complete path, including query args if applicable
  ep=$2
  body_data=$3
  _edgedns_content_type=""
  _request_url_path="$ep"
  _request_body="$body_data"
  _request_method="$m"
  _edgedns_headers=""
  tab=""
  _edgedns_headers="${_edgedns_headers}${tab}Host: ${AKAMAI_HOST}"
  tab="\t"
  # Set in acme.sh _post/_get
  #_edgedns_headers="${_edgedns_headers}${tab}User-Agent:ACME DNSAPI Edge DNS version ${ACME_EDGEDNS_VERSION}"
  _edgedns_headers="${_edgedns_headers}${tab}Accept: application/json"
  if [ "$m" != "GET" ] && [ "$m" != "DELETE" ] ; then
    _edgedns_content_type="application/json;charset=UTF-8"
    _utf8_body_data="$(echo -n "$ _request_body" | iconv -t utf-8)"
    _utf8_body_len="$(echo -n "$_utf8_body_data"  | awk '{print length}')"
    _edgedns_headers="${_edgedns_headers}${tab}Content-Length: ${_utf8_body_len}"
  fi
  _made_auth_header=$(_edgedns_make_auth_header)
  _edgedns_headers="${_edgedns_headers}${tab}Authorization: ${_made_auth_header}"
  _secure_debug2 "Made Auth Header" "${_made_auth_header}"
  hdr_indx=1
  work_header="${_edgedns_headers}${tab}"
  _debug3 "work_header" "${work_header}"
  while [ "${work_header}" ]; do  
    entry="${work_header%%\\t*}"; work_header="${work_header#*\\t}"
    export "$(printf "_H%s=%s" "${hdr_indx}" "${entry}")"
    _debug2 "Request Header " "${entry}"
    hdr_indx=$(( hdr_indx + 1 ))
  done
 
  # clear headers from previous request to avoid getting wrong http code on timeouts
  :>"$HTTP_HEADER"
  _debug "$ep"
  if [ "$m" != "GET" ]; then
    _debug "Method data" "$data"
    # body  url [needbase64] [POST|PUT|DELETE] [ContentType]
    response="$(_post "$_utf8_body_data" "$ep" false "$m")"
  else
    response="$(_get "$ep")"
  fi

  _ret="$?"
  _debug "response" "$response"
  _code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\\r\\n")"
  _debug2 "http response code" "$_code"

  if [ "$_code" = "200" ] || [ "$_code" = "201" ]; then
    # All good
    response="$(echo "$response" | _normalizeJson)"
    echo -n "${response}"
    return 0
  fi

  if [ "$_code" = "204" ]; then
    # Success, no body
    echo -n ""
    return 0
  fi

  if [ "$_code" = "400" ]; then
    _err "Bad request presented"
    _log "$(printf "Headers: %s" "$_edgedns_headers")"
    _log "$(printf "Method: %s" "$_request_method")"
    _log "$(printf "URL: %s" "$ep")"
    _log "$(printf "Data: %s" "$data")"
  fi

  if [ "$_code" = "403" ]; then
    _err "access denied make sure your Edgegrid cedentials are correct."
  fi

  echo "$_code"
  return 1
}

_edgedns_eg_timestamp() {
  _eg_timestamp=$(date -u "+%Y%m%dT%H:%M:%S+0000")
}

_edgedns_new_nonce() {
  _nonce=$(uuidgen -r)
}

_edgedns_make_auth_header() {
  _debug "Constructing Auth Header"
  _edgedns_eg_timestamp 
  _edgedns_new_nonce 
  # "Unsigned authorization header: 'EG1-HMAC-SHA256 client_token=block;access_token=block;timestamp=20200806T14:16:33+0000;nonce=72cde72c-82d9-4721-9854-2ba057929d67;'"
  _auth_header="$(printf "EG1-HMAC-SHA256 client_token=%s;access_token=%s;timestamp=%s;nonce=%s;" "${AKAMAI_CLIENT_TOKEN}" "${AKAMAI_ACCESS_TOKEN}" "${_eg_timestamp}" "${_nonce}")" 
  _secure_debug2 "Unsigned Auth Header: " "$_auth_header"

  _sig="$(_edgedns_sign_request)"
  _signed_auth_header="$(printf "%ssignature=%s" "${_auth_header}" "${_sig}")"
  _secure_debug2 "Signed Auth Header: " "${_signed_auth_header}" 
  echo -n "${_signed_auth_header}"
}

_edgedns_sign_request() {
  _debug2 "Signing http request"
  _signed_data=$(_edgedns_make_data_to_sign "${_auth_header}")
  _secure_debug2 "Returned signed data" "$_signed_data"
  _key=$(_edgedns_make_signing_key "${_eg_timestamp}")
  _signed_req=$(_edgedns_base64_hmac_sha256 "$_signed_data" "$_key")
  _secure_debug2 "Signed Request" "${_signed_req}"
  echo -n "${_signed_req}"
}

_edgedns_make_signing_key() {
  _debug2 "Creating sigining key"
  ts=$1
  _signing_key=$(_edgedns_base64_hmac_sha256 "$ts" "${AKAMAI_CLIENT_SECRET}")
  _secure_debug2 "Signing Key" "${_signing_key}"
  echo -n "${_signing_key}"  

}

_edgedns_make_data_to_sign() {
  _debug2 "Processing data to sign"
  hdr=$1
  _secure_debug2 "hdr" "$hdr"
  content_hash=$(_edgedns_make_content_hash)
  path="$(echo -n "${_request_url_path}" |sed 's/https\?:\/\///')"
  path="${path#*$AKAMAI_HOST}"
  _debug "hier path" "${path}"
  # dont expose headers to sign so use MT string
  data="$(printf "%s\thttps\t%s\t%s\t%s\t%s\t%s" "${_request_method}" "${AKAMAI_HOST}" "${path}" "" "${content_hash}" "$hdr")"
  _secure_debug2 "Data to Sign" "${data}"
  echo -n "${data}"
}

_edgedns_make_content_hash() {
  _debug2 "Generating content hash"
  prep_body=""
  _hash=""
  _debug2 "Request method" "${_request_method}"
  if [ "${_request_method}" != "POST" ] || [ -z "${_request_body}" ]; then
    echo -n "${prep_body}"
    return 0
  fi
  prep_body="$(echo -n "${_request_body}")"
  _debug2 "Req body" "${prep_body}"
  _hash=$(_edgedns_base64_sha256 "${prep_body}")
  _debug2 "Content hash" "${_hash}"
  echo -n "${_hash}"
}

_edgedns_base64_hmac_sha256() {
  _debug2 "Generating hmac"
  data=$1
  key=$2
  encoded_data="$(echo -n "${data}" | iconv -t utf-8)"
  encoded_key="$(echo -n "${key}" | iconv -t utf-8)"
  _secure_debug2 "encoded data" "${encoded_data}"
  _secure_debug2 "encoded key" "${encoded_key}"
  #key_hex="$(_durl_replace_base64 "$key" | _dbase64 | _hex_dump | tr -d ' ')"
  #data_sig="$(printf "%s" "$encoded_data" | _hmac sha256 "${key_hex}" | _base64 | _url_replace)"

  data_sig="$(echo -n "$encoded_data" | ${ACME_OPENSSL_BIN:-openssl} dgst -sha256 -hmac $encoded_key -binary | _base64)"
  _secure_debug2 "data_sig:" "${data_sig}"
  out="$(echo -n "${data_sig}" | iconv -f utf-8)"
  _secure_debug2 "hmac" "${out}"
  echo -n "${out}"
}

_edgedns_base64_sha256() {
  _debug2 "Creating sha256 digest"
  trg=$1
  utf8_str="$(echo -n "${trg}" | iconv -t utf-8)"
  _secure_debug2 "digest data" "$trg"
  _secure_debug2 "encoded digest data" "${utf8_str}"
  digest="$(echo -n "${trg}" | ${ACME_OPENSSL_BIN:-openssl} dgst -sha256 -binary | _base64)"
  out="$(echo -n "${digest}" | iconv -f utf-8)"
  _secure_debug2 "digest decode" "${out}"
  echo -n "${out}"
}

#_edgedns_parse_edgerc() {
#  filepath=$1
#  section=$2
#}


