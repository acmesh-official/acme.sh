#!/usr/bin/env sh

# Akamai Edge DNS v2  API
# User must provide Open Edgegrid API credentials to the EdgeDNS installation. The remote user in EdgeDNS must have CRUD access to
# Edge DNS Zones and Recordsets, e.g. DNS—Zone Record Management authorization

# Report bugs to https://control.akamai.com/apps/support-ui/#/contact-support

# Values to export:
# --EITHER--
# *** TBD. NOT IMPLEMENTED YET ***
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

  _debug2 "Add: zone" "$zone"
  acmeRecordURI=$(printf "%s/%s/names/%s/types/TXT" "$edge_endpoint" "$zone" "$fulldomain")
  _debug3 "Add URL" "$acmeRecordURI"
  # Get existing TXT record
  _edge_result=$(_edgedns_rest GET "$acmeRecordURI")
  _api_status="$?"
  _debug3 "_edge_result" "$_edge_result"
  if [ "$_api_status" -ne 0 ]; then
    if [ "$curResult" = "FATAL" ]; then
      _err "$(printf "Fatal error: acme API function call : %s" "$retVal")"
    fi
    if [ "$_edge_result" != "404" ]; then
      _err "$(printf "Failure accessing Akamai Edge DNS API Server. Error: %s" "$_edge_result")"
      return 1
    fi
  fi
  rdata="\"${txtvalue}\""
  record_op="POST"
  if [ "$_api_status" -eq 0 ]; then
    # record already exists. Get existing record data and update
    record_op="PUT"
    rdlist="${_edge_result#*\"rdata\":[}"
    rdlist="${rdlist%%]*}"
    rdlist=$(echo "$rdlist" | tr -d '"' | tr -d "\\\\")
    _debug3 "existing TXT found"
    _debug3 "record data" "$rdlist"
    # value already there?
    if _contains "$rdlist" "$txtvalue"; then
      return 0
    fi
    _txt_val=""
    while [ "$_txt_val" != "$rdlist" ] && [ "${rdlist}" ]; do
      _txt_val="${rdlist%%,*}"
      rdlist="${rdlist#*,}"
      rdata="${rdata},\"${_txt_val}\""
    done
  fi
  # Add the txtvalue TXT Record
  body="{\"name\":\"$fulldomain\",\"type\":\"TXT\",\"ttl\":600, \"rdata\":"[${rdata}]"}"
  _debug3 "Add body '${body}'"
  _edge_result=$(_edgedns_rest "$record_op" "$acmeRecordURI" "$body")
  _api_status="$?"
  if [ "$_api_status" -eq 0 ]; then
    _log "$(printf "Text value %s added to recordset %s" "$txtvalue" "$fulldomain")"
    return 0
  else
    _err "$(printf "error adding TXT record for validation. Error: %s" "$_edge_result")"
    return 1
  fi
}

# Usage: dns_edgedns_rm   _acme-challenge.www.domain.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
# Used to delete txt record
#
dns_edgedns_rm() {
  fulldomain=$1
  txtvalue=$2
  _debug "ENTERING DNS_EDGEDNS_RM"
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
  _debug2 "RM: zone" "${zone}"
  acmeRecordURI=$(printf "%s/%s/names/%s/types/TXT" "${edge_endpoint}" "$zone" "$fulldomain")
  _debug3 "RM URL" "$acmeRecordURI"
  # Get existing TXT record
  _edge_result=$(_edgedns_rest GET "$acmeRecordURI")
  _api_status="$?"
  if [ "$_api_status" -ne 0 ]; then
    if [ "$curResult" = "FATAL" ]; then
      _err "$(printf "Fatal error: acme API function call : %s" "$retVal")"
    fi
    if [ "$_edge_result" != "404" ]; then
      _err "$(printf "Failure accessing Akamai Edge DNS API Server. Error: %s" "$_edge_result")"
      return 1
    fi
  fi
  _debug3 "_edge_result" "$_edge_result"
  record_op="DELETE"
  body=""
  if [ "$_api_status" -eq 0 ]; then
    # record already exists. Get existing record data and update
    rdlist="${_edge_result#*\"rdata\":[}"
    rdlist="${rdlist%%]*}"
    rdlist=$(echo "$rdlist" | tr -d '"' | tr -d "\\\\")
    _debug3 "rdlist" "$rdlist"
    if [ -n "$rdlist" ]; then
      record_op="PUT"
      comma=""
      rdata=""
      _txt_val=""
      while [ "$_txt_val" != "$rdlist" ] && [ "$rdlist" ]; do
        _txt_val="${rdlist%%,*}"
        rdlist="${rdlist#*,}"
        _debug3 "_txt_val" "$_txt_val"
        _debug3 "txtvalue" "$txtvalue"
        if ! _contains "$_txt_val" "$txtvalue"; then
          rdata="${rdata}${comma}\"${_txt_val}\""
          comma=","
        fi
      done
      if [ -z "$rdata" ]; then
        record_op="DELETE"
      else
        # Recreate the txtvalue TXT Record
        body="{\"name\":\"$fulldomain\",\"type\":\"TXT\",\"ttl\":600, \"rdata\":"[${rdata}]"}"
        _debug3 "body" "$body"
      fi
    fi
  fi
  _edge_result=$(_edgedns_rest "$record_op" "$acmeRecordURI" "$body")
  _api_status="$?"
  if [ "$_api_status" -eq 0 ]; then
    _log "$(printf "Text value %s removed from recordset %s" "$txtvalue" "$fulldomain")"
    return 0
  else
    _err "$(printf "error removing TXT record for validation. Error: %s" "$_edge_result")"
    return 1
  fi
}

####################  Private functions below ##################################

_EDGEDNS_credentials() {
  _debug "GettingEdge DNS credentials"
  _log "$(printf "ACME DNSAPI Edge DNS version %s" ${ACME_EDGEDNS_VERSION})"
  args_missing=0
  if [ -z "$AKAMAI_ACCESS_TOKEN" ]; then
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
  if [ -z "$AKAMAI_HOST" ]; then
    AKAMAI_ACCESS_TOKEN=""
    AKAMAI_CLIENT_TOKEN=""
    AKAMAI_HOST=""
    AKAMAI_CLIENT_SECRET=""
    _err "AKAMAI_HOST is missing"
    args_missing=1
  fi
  if [ -z "$AKAMAI_CLIENT_SECRET" ]; then
    AKAMAI_ACCESS_TOKEN=""
    AKAMAI_CLIENT_TOKEN=""
    AKAMAI_HOST=""
    AKAMAI_CLIENT_SECRET=""
    _err "AKAMAI_CLIENT_SECRET is missing"
    args_missing=1
  fi

  if [ "$args_missing" = 1 ]; then
    _err "You have not properly specified the EdgeDNS Open Edgegrid API credentials. Please try again."
    return 1
  else
    _saveaccountconf_mutable AKAMAI_ACCESS_TOKEN "$AKAMAI_ACCESS_TOKEN"
    _saveaccountconf_mutable AKAMAI_CLIENT_TOKEN "$AKAMAI_CLIENT_TOKEN"
    _saveaccountconf_mutable AKAMAI_HOST "$AKAMAI_HOST"
    _saveaccountconf_mutable AKAMAI_CLIENT_SECRET "$AKAMAI_CLIENT_SECRET"
    # Set whether curl should use secure or insecure mode
  fi
  export HTTPS_INSECURE=0 # All Edgegrid API calls are secure
  edge_endpoint=$(printf "https://%s/config-dns/v2/zones" "$AKAMAI_HOST")
  _debug3 "Edge API Endpoint:" "$edge_endpoint"

}

_EDGEDNS_getZoneInfo() {
  _debug "Getting Zoneinfo"
  zoneEnd=false
  curZone=$1
  while [ -n "$zoneEnd" ]; do
    # we can strip the first part of the fulldomain, since its just the _acme-challenge string
    curZone="${curZone#*.}"
    # suffix . needed for zone -> domain.tld.
    # create zone get url
    get_zone_url=$(printf "%s/%s" "$edge_endpoint" "$curZone")
    _debug3 "Zone Get: " "${get_zone_url}"
    curResult=$(_edgedns_rest GET "$get_zone_url")
    retVal=$?
    if [ "$retVal" -ne 0 ]; then
      if [ "$curResult" = "FATAL" ]; then
        _err "$(printf "Fatal error: acme API function call : %s" "$retVal")"
      fi
      if [ "$curResult" != "404" ]; then
        _err "$(printf "Managed zone validation failed. Error response: %s" "$retVal")"
        return 1
      fi
    fi
    if _contains "$curResult" "\"zone\":"; then
      _debug2 "Zone data" "${curResult}"
      zone=$(echo "${curResult}" | _egrep_o "\"zone\"\\s*:\\s*\"[^\"]*\"" | _head_n 1 | cut -d : -f 2 | tr -d "\"")
      _debug3 "Zone" "${zone}"
      zoneEnd=""
      return 0
    fi

    if [ "${curZone#*.}" != "$curZone" ]; then
      _debug3 "$(printf "%s still contains a '.' - so we can check next higher level" "$curZone")"
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
  _edgedns_headers="${_edgedns_headers}${tab}Accept: application/json,*/*"
  if [ "$m" != "GET" ] && [ "$m" != "DELETE" ]; then
    _edgedns_content_type="application/json"
    _debug3 "_request_body" "$_request_body"
    _body_len=$(echo "$_request_body" | tr -d "\n\r" | awk '{print length}')
    _edgedns_headers="${_edgedns_headers}${tab}Content-Length: ${_body_len}"
  fi
  _edgedns_make_auth_header
  _edgedns_headers="${_edgedns_headers}${tab}Authorization: ${_signed_auth_header}"
  _secure_debug2 "Made Auth Header" "$_signed_auth_header"
  hdr_indx=1
  work_header="${_edgedns_headers}${tab}"
  _debug3 "work_header" "$work_header"
  while [ "$work_header" ]; do
    entry="${work_header%%\\t*}"
    work_header="${work_header#*\\t}"
    export "$(printf "_H%s=%s" "$hdr_indx" "$entry")"
    _debug2 "Request Header " "$entry"
    hdr_indx=$((hdr_indx + 1))
  done

  # clear headers from previous request to avoid getting wrong http code on timeouts
  : >"$HTTP_HEADER"
  _debug2 "$ep"
  if [ "$m" != "GET" ]; then
    _debug3 "Method data" "$data"
    # body  url [needbase64] [POST|PUT|DELETE] [ContentType]
    response=$(_post "$_request_body" "$ep" false "$m" "$_edgedns_content_type")
  else
    response=$(_get "$ep")
  fi
  _ret="$?"
  if [ "$_ret" -ne 0 ]; then
    _err "$(printf "acme.sh API function call failed. Error: %s" "$_ret")"
    echo "FATAL"
    return "$_ret"
  fi
  _debug2 "response" "${response}"
  _code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\\r\\n")"
  _debug2 "http response code" "$_code"
  if [ "$_code" = "200" ] || [ "$_code" = "201" ]; then
    # All good
    response="$(echo "${response}" | _normalizeJson)"
    echo "$response"
    return 0
  fi

  if [ "$_code" = "204" ]; then
    # Success, no body
    echo "$_code"
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
  _debug "Generating signature Timestamp"
  _debug3 "Retriving ntp time"
  _timeheaders="$(_get "https://www.ntp.org" "onlyheader")"
  _debug3 "_timeheaders" "$_timeheaders"
  _ntpdate="$(echo "$_timeheaders" | grep -i "Date:" | _head_n 1 | cut -d ':' -f 2- | tr -d "\r\n")"
  _debug3 "_ntpdate" "$_ntpdate"
  _ntpdate="$(echo "${_ntpdate}" | sed -e 's/^[[:space:]]*//')"
  _debug3 "_NTPDATE" "$_ntpdate"
  _ntptime="$(echo "${_ntpdate}" | _head_n 1 | cut -d " " -f 5 | tr -d "\r\n")"
  _debug3 "_ntptime" "$_ntptime"
  _eg_timestamp=$(date -u "+%Y%m%dT")
  _eg_timestamp="$(printf "%s%s+0000" "$_eg_timestamp" "$_ntptime")"
  _debug "_eg_timestamp" "$_eg_timestamp"
}

_edgedns_new_nonce() {
  _debug "Generating Nonce"
  _nonce=$(echo "EDGEDNS$(_time)" | _digest sha1 hex | cut -c 1-32)
  _debug3 "_nonce" "$_nonce"
}

_edgedns_make_auth_header() {
  _debug "Constructing Auth Header"
  _edgedns_new_nonce
  _edgedns_eg_timestamp
  # "Unsigned authorization header: 'EG1-HMAC-SHA256 client_token=block;access_token=block;timestamp=20200806T14:16:33+0000;nonce=72cde72c-82d9-4721-9854-2ba057929d67;'"
  _auth_header="$(printf "EG1-HMAC-SHA256 client_token=%s;access_token=%s;timestamp=%s;nonce=%s;" "$AKAMAI_CLIENT_TOKEN" "$AKAMAI_ACCESS_TOKEN" "$_eg_timestamp" "$_nonce")"
  _secure_debug2 "Unsigned Auth Header: " "$_auth_header"

  _edgedns_sign_request
  _signed_auth_header="$(printf "%ssignature=%s" "$_auth_header" "$_signed_req")"
  _secure_debug2 "Signed Auth Header: " "${_signed_auth_header}"
}

_edgedns_sign_request() {
  _debug2 "Signing http request"
  _edgedns_make_data_to_sign "$_auth_header"
  _secure_debug2 "Returned signed data" "$_mdata"
  _edgedns_make_signing_key "$_eg_timestamp"
  _edgedns_base64_hmac_sha256 "$_mdata" "$_signing_key"
  _signed_req="$_hmac_out"
  _secure_debug2 "Signed Request" "$_signed_req"
}

_edgedns_make_signing_key() {
  _debug2 "Creating sigining key"
  ts=$1
  _edgedns_base64_hmac_sha256 "$ts" "$AKAMAI_CLIENT_SECRET"
  _signing_key="$_hmac_out"
  _secure_debug2 "Signing Key" "$_signing_key"

}

_edgedns_make_data_to_sign() {
  _debug2 "Processing data to sign"
  hdr=$1
  _secure_debug2 "hdr" "$hdr"
  _edgedns_make_content_hash
  path="$(echo "$_request_url_path" | tr -d "\n\r" | sed 's/https\?:\/\///')"
  path="${path#*$AKAMAI_HOST}"
  _debug "hier path" "$path"
  # dont expose headers to sign so use MT string
  _mdata="$(printf "%s\thttps\t%s\t%s\t%s\t%s\t%s" "$_request_method" "$AKAMAI_HOST" "$path" "" "$_hash" "$hdr")"
  _secure_debug2 "Data to Sign" "$_mdata"
}

_edgedns_make_content_hash() {
  _debug2 "Generating content hash"
  _hash=""
  _debug2 "Request method" "${_request_method}"
  if [ "$_request_method" != "POST" ] || [ -z "$_request_body" ]; then
    return 0
  fi
  _debug2 "Req body" "$_request_body"
  _edgedns_base64_sha256 "$_request_body"
  _hash="$_sha256_out"
  _debug2 "Content hash" "$_hash"
}

_edgedns_base64_hmac_sha256() {
  _debug2 "Generating hmac"
  data=$1
  key=$2
  encoded_data="$(echo "$data" | iconv -t utf-8)"
  encoded_key="$(echo "$key" | iconv -t utf-8)"
  _secure_debug2 "encoded data" "$encoded_data"
  _secure_debug2 "encoded key" "$encoded_key"

  encoded_key_hex=$(printf "%s" "$encoded_key" | _hex_dump | tr -d ' ')
  data_sig="$(echo "$encoded_data" | tr -d "\n\r" | _hmac sha256 "$encoded_key_hex" | _base64)"

  _secure_debug2 "data_sig:" "$data_sig"
  _hmac_out="$(echo "$data_sig" | tr -d "\n\r" | iconv -f utf-8)"
  _secure_debug2 "hmac" "$_hmac_out"
}

_edgedns_base64_sha256() {
  _debug2 "Creating sha256 digest"
  trg=$1
  _secure_debug2 "digest data" "$trg"
  digest="$(echo "$trg" | tr -d "\n\r" | _digest "sha256")"
  _sha256_out="$(echo "$digest" | tr -d "\n\r" | iconv -f utf-8)"
  _secure_debug2 "digest decode" "$_sha256_out"
}

#_edgedns_parse_edgerc() {
#  filepath=$1
#  section=$2
#}
