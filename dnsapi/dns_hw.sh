#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_hw_info='Huawei Cloud DNS
Site: HuaweiCloud.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_hw
Options:
 HW_AK Access Key
 HW_SK Secret Access Key
 HW_Region Region. E.g. "cn-north-4". Optional, defaults to "cn-north-4".
Issues: github.com/acmesh-official/acme.sh/issues/7221
Author: mashirozx
'

dns_hw_add() {
  fulldomain=$1
  txtvalue=$2

  if ! _hw_init; then
    return 1
  fi

  if ! _hw_get_zoneid "$fulldomain"; then
    return 1
  fi
  if ! _hw_get_recordset "$fulldomain" "$_hw_zoneid"; then
    return 1
  fi

  # Huawei Cloud stores each TXT value with its required inner quotes.
  _hw_txt_record="\"\\\"${txtvalue}\\\"\""
  case "$_hw_records" in
  *"$txtvalue"*)
    _debug "TXT record already exists"
    ;;
  *)
    if [ -z "$_hw_recordid" ]; then
      _hw_body="{\"name\":\"${fulldomain}.\",\"type\":\"TXT\",\"ttl\":300,\"records\":[${_hw_txt_record}]}"
      # Create a TXT record set: https://support.huaweicloud.com/api-dns/dns_api_64001.html
      _hw_rest "POST" "/v2/zones/${_hw_zoneid}/recordsets" "" "$_hw_body" || return 1
    else
      _hw_body="{\"name\":\"${fulldomain}.\",\"type\":\"TXT\",\"ttl\":${_hw_recordttl},\"records\":[${_hw_records},${_hw_txt_record}]}"
      # Update the existing TXT record set: https://support.huaweicloud.com/api-dns/UpdateRecordSets.html
      _hw_rest "PUT" "/v2/zones/${_hw_zoneid}/recordsets/${_hw_recordid}" "" "$_hw_body" || return 1
    fi
    ;;
  esac

  _saveaccountconf_mutable HW_AK "$HW_AK"
  _saveaccountconf_mutable HW_SK "$HW_SK"
  if [ -n "$HW_Region" ]; then
    _saveaccountconf_mutable HW_Region "$HW_Region"
  fi
}

dns_hw_rm() {
  fulldomain=$1
  txtvalue=$2

  if ! _hw_init; then
    return 1
  fi

  if ! _hw_get_zoneid "$fulldomain" || ! _hw_get_recordset "$fulldomain" "$_hw_zoneid"; then
    return 1
  fi
  if [ -z "$_hw_recordid" ]; then
    _debug "TXT record not found"
    return 0
  fi

  # Keep unrelated TXT values that share this record set.
  _hw_txt_record="\"\\\"${txtvalue}\\\"\""
  case "$_hw_records" in
  *"$txtvalue"*) ;;
  *)
    _debug "TXT record value not found"
    return 0
    ;;
  esac
  _hw_sed_txt_record=$(echo "$_hw_txt_record" | sed 's/\\/\\\\/g')
  _hw_new_records=$(echo "$_hw_records" | sed "s/${_hw_sed_txt_record},//; s/,${_hw_sed_txt_record}//; s/${_hw_sed_txt_record}//")
  if [ -z "$_hw_new_records" ]; then
    # Delete an empty TXT record set: https://support.huaweicloud.com/api-dns/dns_api_64005.html
    _hw_rest "DELETE" "/v2/zones/${_hw_zoneid}/recordsets/${_hw_recordid}" "" "" || return 1
  else
    _hw_body="{\"name\":\"${fulldomain}.\",\"type\":\"TXT\",\"ttl\":${_hw_recordttl},\"records\":[${_hw_new_records}]}"
    # Update the record set after removing this challenge value: https://support.huaweicloud.com/api-dns/UpdateRecordSets.html
    _hw_rest "PUT" "/v2/zones/${_hw_zoneid}/recordsets/${_hw_recordid}" "" "$_hw_body" || return 1
  fi
}

_hw_init() {
  # Credentials from the environment override the persisted account settings.
  HW_AK="${HW_AK:-$(_readaccountconf_mutable HW_AK)}"
  HW_SK="${HW_SK:-$(_readaccountconf_mutable HW_SK)}"
  HW_Region="${HW_Region:-$(_readaccountconf_mutable HW_Region)}"
  if [ -z "$HW_AK" ] || [ -z "$HW_SK" ]; then
    _err "You don't specify Huawei Cloud Access Key and Secret Access Key yet."
    return 1
  fi

  _hw_region="${HW_Region:-cn-north-4}"
  _hw_api="https://dns.${_hw_region}.myhuaweicloud.com"
  _hw_host="dns.${_hw_region}.myhuaweicloud.com"
}

_hw_get_zoneid() {
  _hw_domain=$1
  _hw_index=1
  # Try successively shorter suffixes so delegated zones are supported.
  while true; do
    _hw_zone_name=$(echo "$_hw_domain" | cut -d . -f "$_hw_index"-100)
    if [ -z "$_hw_zone_name" ]; then
      _err "Could not find Huawei Cloud DNS zone for $_hw_domain"
      return 1
    fi
    _hw_query="name=$(printf "%s" "$_hw_zone_name" | _url_encode upper-hex)&search_mode=equal"
    # List public zones to find the authoritative zone: https://support.huaweicloud.com/api-dns/dns_api_62003.html
    if ! _hw_rest "GET" "/v2/zones" "$_hw_query" ""; then
      return 1
    fi
    _hw_zoneid=$(echo "$_hw_response" | _egrep_o '"id"[ ]*:[ ]*"[^"]*"' | _head_n 1 | cut -d '"' -f 4)
    _hw_returned_name=$(echo "$_hw_response" | _egrep_o '"name"[ ]*:[ ]*"[^"]*"' | _head_n 1 | cut -d '"' -f 4)
    if [ -n "$_hw_zoneid" ] && [ "$_hw_returned_name" = "${_hw_zone_name}." ]; then
      return 0
    fi
    _hw_index=$(_math "$_hw_index" + 1)
  done
}

_hw_get_recordset() {
  _hw_domain=$1
  _hw_zone=$2
  _hw_recordid=""
  _hw_records=""
  _hw_recordttl=""
  _hw_query="name=$(printf "%s" "$_hw_domain" | _url_encode upper-hex)&search_mode=equal&type=TXT"
  # List TXT record sets to locate the existing challenge record: https://support.huaweicloud.com/api-dns/dns_api_64004.html
  if ! _hw_rest "GET" "/v2/zones/${_hw_zone}/recordsets" "$_hw_query" ""; then
    return 1
  fi
  _hw_recordid=$(echo "$_hw_response" | _egrep_o '"id"[ ]*:[ ]*"[^"]*"' | _head_n 1 | cut -d '"' -f 4)
  _hw_returned_name=$(echo "$_hw_response" | _egrep_o '"name"[ ]*:[ ]*"[^"]*"' | _head_n 1 | cut -d '"' -f 4)
  if [ -z "$_hw_recordid" ]; then
    return 0
  fi
  _hw_expected_name="$(_lower_case "${_hw_domain}.")"
  if [ "$(_lower_case "$_hw_returned_name")" != "$_hw_expected_name" ]; then
    _err "Huawei Cloud DNS returned an unexpected record set for $_hw_domain"
    return 1
  fi
  # A DNS record set may contain multiple TXT values for concurrent challenges.
  _hw_records=$(echo "$_hw_response" | sed 's/.*"records"[ ]*:[ ]*\[//; s/\].*//' | tr -d '\r\n')
  _hw_recordttl=$(echo "$_hw_response" | _egrep_o '"ttl"[ ]*:[ ]*[0-9]*' | _head_n 1 | cut -d : -f 2 | tr -d ' ')
  if [ -z "$_hw_recordttl" ]; then
    _err "Huawei Cloud DNS record set did not include a TTL"
    return 1
  fi
}

_hw_sha256() {
  printf "%s" "$1" | _digest sha256 hex
}

_hw_hmac() {
  _hw_key_hex=$(printf "%s" "$1" | _hex_dump | tr -d ' ')
  printf "%s" "$2" | _hmac sha256 "$_hw_key_hex" hex
}

_hw_rest() {
  _hw_method=$1
  _hw_uri=$2
  _hw_query=$3
  _hw_payload=$4
  _H1=""
  _H2=""
  _H3=""
  _H4=""
  _H5=""
  _hw_date=$(_utc_date | tr -d ' :-')
  _hw_short_date=${_hw_date%??????}
  _hw_date="${_hw_short_date}T${_hw_date#????????}Z"
  # Huawei's API gateway signs a trailing slash even when the published URI has none.
  _hw_canonical_uri="${_hw_uri%/}/"
  # SDK-HMAC-SHA256 signs the exact canonical request sent to Huawei Cloud.
  _hw_payload_hash=$(_hw_sha256 "$_hw_payload")
  _hw_headers="content-type:application/json
host:${_hw_host}
x-sdk-date:${_hw_date}
"
  _hw_signed_headers="content-type;host;x-sdk-date"
  _hw_canonical_request="${_hw_method}
${_hw_canonical_uri}
${_hw_query}
${_hw_headers}
${_hw_signed_headers}
${_hw_payload_hash}"
  _hw_string_to_sign="SDK-HMAC-SHA256
${_hw_date}
$(_hw_sha256 "$_hw_canonical_request")"
  _hw_signature=$(_hw_hmac "$HW_SK" "$_hw_string_to_sign")
  _H1="Content-Type: application/json"
  _H2="Host: ${_hw_host}"
  _H3="X-Sdk-Date: ${_hw_date}"
  _H4="Authorization: SDK-HMAC-SHA256 Access=${HW_AK}, SignedHeaders=${_hw_signed_headers}, Signature=${_hw_signature}"
  _hw_url="${_hw_api}${_hw_uri}"
  if [ -n "$_hw_query" ]; then
    _hw_url="${_hw_url}?${_hw_query}"
  fi
  # _post sends the canonical request with each signed header exactly once.
  if [ -z "$HTTP_HEADER" ]; then
    _err "HTTP header file is not initialized"
    return 1
  fi
  : >"$HTTP_HEADER" || return 1
  if ! _hw_response=$(_post "$_hw_payload" "$_hw_url" "" "$_hw_method"); then
    _err "Huawei Cloud DNS API request failed"
    return 1
  fi
  _hw_code=$(grep '^HTTP' "$HTTP_HEADER" | _tail_n 1 | cut -d ' ' -f 2 | tr -d '\r\n')
  if ! _startswith "$_hw_code" "2"; then
    _err "Huawei Cloud DNS API error: HTTP $_hw_code"
    _debug2 response "$_hw_response"
    return 1
  fi
}
