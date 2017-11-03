#!/bin/bash
########  Public functions #####################
#domain keyfile certfile cafile fullchain
#Ali_Region="cn-hangzhou"
#Ali_Api_Key=""
#Ali_Api_Secret=""
Ali_Api="https://slb.aliyuncs.com/"

ali_slb_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"

  if [ -z "$Ali_Api_Key" ] || [ -z "$Ali_Api_Secret" ]; then
    Ali_Api_Key=""
    Ali_Api_Secret=""
    _err "You don't specify aliyun api key and secret yet."
    return 1
  fi

  #save the api key and secret to the account conf file.
  _saveaccountconf Ali_Api_Key "$Ali_Api_Key"
  _saveaccountconf Ali_Api_Secret "$Ali_Api_Secret"

  #_ali_regions && _ali_rest "Regions"
  _add_slb_ca_query "$_ckey" "$_cfullchain" && _ali_rest "Upload Server Certificate"

  #returns 0 means success, otherwise error.
  return 0
}

########  Private functions #####################
_ali_rest() {

  signature=$(printf "%s" "GET&%2F&$(_ali_urlencode "$query")" | _hmac "sha1" "$(printf "%s" "$Ali_Api_Secret&" | _hex_dump | tr -d " ")" | _base64)
  signature=$(_ali_urlencode "$signature")
  url="$Ali_Api?$query&Signature=$signature"
  if ! response="$(_get "$url" "" 3000)"; then
    _err "Error <$1>"
    return 1
  fi

  if [ -z "$2" ]; then
    message="$(printf "%s" "$response" | _egrep_o "\"Message\":\"[^\"]*\"" | cut -d : -f 2 | tr -d \")"
    if [ -n "$message" ]; then
      _err "$message"
      return 1
    fi
  fi

  _debug response "$response"
  return 0
}

_ali_urlencode() {
  echo $(php -r "echo str_replace(['+','*','%7E'], ['%20','%2A','~'], urlencode(\"$1\"));")
}

_ali_nonce() {
  date +"%s%N"
}

_ali_regions() {
  query=''
  query=$query'AccessKeyId='$Ali_Api_Key
  query=$query'&Action=DescribeRegions'
  query=$query'&Format=json'
  query=$query'&SignatureMethod=HMAC-SHA1'
  query=$query'&SignatureNonce='$(_ali_nonce)
  query=$query'&SignatureVersion=1.0'
  query=$query'&Timestamp='$(_timestamp)
  query=$query'&Version=2014-05-15'
}

#_add_slb_ca_query "$_ckey" "$_cfullchain"
_add_slb_ca_query() {
  ca_key=$(_readfile "$1")
  ca_cert=$(_readfile "$2")
  query=''
  query=$query'AccessKeyId='$Ali_Api_Key
  query=$query'&Action=UploadServerCertificate'
  query=$query'&Format=json'
  query=$query'&PrivateKey='$ca_key
  query=$query'&RegionId='$Ali_Region
  query=$query'&ServerCertificate='$ca_cert
  query=$query'&ServerCertificateName='$(_date)
  query=$query'&SignatureMethod=HMAC-SHA1'
  query=$query'&SignatureNonce='$(_ali_nonce)
  query=$query'&SignatureVersion=1.0'
  query=$query'&Timestamp='$(_timestamp)
  query=$query'&Version=2014-05-15'
}

_readfile() {
  echo $(php -r "echo str_replace(['+','*','%7E'], ['%20','%2A','~'], urlencode(file_get_contents(\"$1\")));")
}

_timestamp() {
  date -u +"%Y-%m-%dT%H%%3A%M%%3A%SZ"
}

_date() {
  date -u +"%Y%m%d"
}
