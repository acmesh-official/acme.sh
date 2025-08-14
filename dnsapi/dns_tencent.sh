#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_tencent_info='Tencent.com
Site: cloud.Tencent.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_tencent
Options:
 Tencent_SecretId Secret ID
 Tencent_SecretKey Secret Key
Issues: github.com/acmesh-official/acme.sh/issues/4781
'
Tencent_API="https://dnspod.tencentcloudapi.com"

#Usage: dns_tencent_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_tencent_add() {
  fulldomain=$1
  txtvalue=$2

  Tencent_SecretId="${Tencent_SecretId:-$(_readaccountconf_mutable Tencent_SecretId)}"
  Tencent_SecretKey="${Tencent_SecretKey:-$(_readaccountconf_mutable Tencent_SecretKey)}"
  if [ -z "$Tencent_SecretId" ] || [ -z "$Tencent_SecretKey" ]; then
    Tencent_SecretId=""
    Tencent_SecretKey=""
    _err "You don't specify tencent api SecretId and SecretKey yet."
    return 1
  fi

  #save the api SecretId and SecretKey to the account conf file.
  _saveaccountconf_mutable Tencent_SecretId "$Tencent_SecretId"
  _saveaccountconf_mutable Tencent_SecretKey "$Tencent_SecretKey"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    return 1
  fi

  _debug "Add record"
  _add_record_query "$_domain" "$_sub_domain" "$txtvalue" && _tencent_rest "CreateRecord"
}

dns_tencent_rm() {
  fulldomain=$1
  txtvalue=$2
  Tencent_SecretId="${Tencent_SecretId:-$(_readaccountconf_mutable Tencent_SecretId)}"
  Tencent_SecretKey="${Tencent_SecretKey:-$(_readaccountconf_mutable Tencent_SecretKey)}"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    return 1
  fi

  _debug "Get record list"
  attempt=1
  max_attempts=5
  while [ -z "$record_id" ] && [ "$attempt" -le $max_attempts ]; do
    _check_exist_query "$_domain" "$_sub_domain" "$txtvalue" && _tencent_rest "DescribeRecordFilterList"
    record_id="$(echo "$response" | _egrep_o "\"RecordId\":\s*[0-9]+" | _egrep_o "[0-9]+")"
    _debug2 record_id "$record_id"
    if [ -z "$record_id" ]; then
      _debug "Due to TencentCloud API synchronization delay, record not found, waiting 10 seconds and retrying"
      _sleep 10
      attempt=$(_math "$attempt + 1")
    fi
  done

  record_id="$(echo "$response" | _egrep_o "\"RecordId\":\s*[0-9]+" | _egrep_o "[0-9]+")"
  _debug2 record_id "$record_id"

  if [ -z "$record_id" ]; then
    _debug "record not found after $max_attempts attempts, skip"
  else
    _debug "Delete record"
    _delete_record_query "$record_id" && _tencent_rest "DeleteRecord"
  fi
}

####################  Private functions below ##################################

_get_root() {
  domain=$1
  i=1
  p=1
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    _describe_records_query "$h" "@"
    if ! _tencent_rest "DescribeRecordList" "ignore"; then
      return 1
    fi

    if _contains "$response" "\"TotalCount\":"; then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-"$p")
      _debug _sub_domain "$_sub_domain"
      _domain="$h"
      _debug _domain "$_domain"
      return 0
    fi
    p="$i"
    i=$(_math "$i" + 1)
  done
  return 1
}

_tencent_rest() {
  action=$1
  service="dnspod"
  payload="${query}"
  timestamp=$(date -u +%s)

  token=$(tencent_signature_v3 $service "$action" "$payload" "$timestamp")
  version="2021-03-23"

  if ! response="$(tencent_api_request $service $version "$action" "$payload" "$timestamp")"; then
    _err "Error <$1>"
    return 1
  fi

  _debug2 response "$response"
  if [ -z "$2" ]; then
    message="$(echo "$response" | _egrep_o "\"Message\":\"[^\"]*\"" | cut -d : -f 2 | tr -d \")"
    if [ "$message" ]; then
      _err "$message"
      return 1
    fi
  fi
}

_add_record_query() {
  query="{\"Domain\":\"$1\",\"SubDomain\":\"$2\",\"RecordType\":\"TXT\",\"RecordLineId\":\"0\",\"RecordLine\":\"0\",\"Value\":\"$3\",\"TTL\":600}"
}

_describe_records_query() {
  query="{\"Domain\":\"$1\",\"Limit\":3000}"
}

_delete_record_query() {
  query="{\"Domain\":\"$_domain\",\"RecordId\":$1}"
}

_check_exist_query() {
  _domain="$1"
  _subdomain="$2"
  _value="$3"
  query="{\"Domain\":\"$_domain\",\"SubDomain\":\"$_subdomain\",\"RecordValue\":\"$_value\"}"
}

# shell client for tencent cloud api v3 | @author: rehiy

tencent_sha256() {
  printf %b "$@" | _digest sha256 hex
}

tencent_hmac_sha256() {
  k=$1
  shift
  hex_key=$(printf %b "$k" | _hex_dump | tr -d ' ')
  printf %b "$@" | _hmac sha256 "$hex_key" hex
}

tencent_hmac_sha256_hexkey() {
  k=$1
  shift
  printf %b "$@" | _hmac sha256 "$k" hex
}

tencent_signature_v3() {
  service=$1
  action=$(echo "$2" | _lower_case)
  payload=${3:-'{}'}
  timestamp=${4:-$(date +%s)}

  domain="$service.tencentcloudapi.com"
  secretId=${Tencent_SecretId:-'tencent-cloud-secret-id'}
  secretKey=${Tencent_SecretKey:-'tencent-cloud-secret-key'}

  algorithm='TC3-HMAC-SHA256'
  date=$(date -u -d "@$timestamp" +%Y-%m-%d 2>/dev/null)
  [ -z "$date" ] && date=$(date -u -r "$timestamp" +%Y-%m-%d)

  canonicalUri='/'
  canonicalQuery=''
  canonicalHeaders="content-type:application/json\nhost:$domain\nx-tc-action:$action\n"

  signedHeaders='content-type;host;x-tc-action'
  canonicalRequest="POST\n$canonicalUri\n$canonicalQuery\n$canonicalHeaders\n$signedHeaders\n$(tencent_sha256 "$payload")"

  credentialScope="$date/$service/tc3_request"
  stringToSign="$algorithm\n$timestamp\n$credentialScope\n$(tencent_sha256 "$canonicalRequest")"

  secretDate=$(tencent_hmac_sha256 "TC3$secretKey" "$date")
  secretService=$(tencent_hmac_sha256_hexkey "$secretDate" "$service")
  secretSigning=$(tencent_hmac_sha256_hexkey "$secretService" 'tc3_request')
  signature=$(tencent_hmac_sha256_hexkey "$secretSigning" "$stringToSign")

  echo "$algorithm Credential=$secretId/$credentialScope, SignedHeaders=$signedHeaders, Signature=$signature"
}

tencent_api_request() {
  service=$1
  version=$2
  action=$3
  payload=${4:-'{}'}
  timestamp=${5:-$(date +%s)}

  token=$(tencent_signature_v3 "$service" "$action" "$payload" "$timestamp")

  _H1="Content-Type: application/json"
  _H2="Authorization: $token"
  _H3="X-TC-Version: $version"
  _H4="X-TC-Timestamp: $timestamp"
  _H5="X-TC-Action: $action"

  _post "$payload" "$Tencent_API" "" "POST" "application/json"
}
