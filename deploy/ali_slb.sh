#!/bin/bash

# Attention:
#This file name is "ali_slb.sh"
#So, here must be a method  ali_slb_deploy()
#Which will be called by acme.sh to deploy the cert
#returns 0 means success, otherwise error.

########  Public functions #####################
# 参考: https://github.com/Neilpang/acme.sh/wiki/DNS-API-Dev-Guide
#domain keyfile certfile cafile fullchain
#Ali_SLB_Region="My_SLB_Region"
#Ali_SLB_Access_Id="My_SLB_Access_Id"
#Ali_SLB_Access_Secret="My_SLB_Access_Secret"
Ali_SLB_Domain="https://slb.aliyuncs.com/"

ali_slb_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"

  if [ -z "$Ali_SLB_Access_Id" ] || [ -z "$Ali_SLB_Access_Secret" ]; then
    Ali_SLB_Access_Id=""
    Ali_SLB_Access_Secret=""
    _err "You don't specify aliyun api key and secret yet."
    return 1
  fi

  #save the api key and secret to the account conf file.
  _saveaccountconf_mutable Ali_SLB_Access_Id "$Ali_SLB_Access_Id"
  _saveaccountconf_mutable Ali_SLB_Access_Secret "$Ali_SLB_Access_Secret"

  #_ali_regions && _ali_rest "Regions"
  _add_slb_ca_query "$_ckey" "$_cfullchain" && _ali_rest "Upload Server Certificate"

  #returns 0 means success, otherwise error.
  return 0
}

########  Private functions #####################
_ali_rest() {

  signature=$(printf "%s" "GET&%2F&$(_ali_urlencode "$query")" | _hmac "sha1" "$(printf "%s" "$Ali_SLB_Access_Secret&" | _hex_dump | tr -d " ")" | _base64)
  signature=$(_ali_urlencode "$signature")
  url="$Ali_SLB_Domain?$query&Signature=$signature"
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

  # 上传证书成功, 将证书绑定到监听端口443
  _set_slb_server_certificate && _ali_set_slb_server_certificate "Set Server Certificate on port 443"

  return 0
}

_ali_set_slb_server_certificate() {

  signature=$(printf "%s" "GET&%2F&$(_ali_urlencode "$query")" | _hmac "sha1" "$(printf "%s" "$Ali_SLB_Access_Secret&" | _hex_dump | tr -d " ")" | _base64)
  signature=$(_ali_urlencode "$signature")
  url="$Ali_SLB_Domain?$query&Signature=$signature"
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
  query=$query'&Action=UploadServerCertificate'
  query=$query'&RegionId='$Ali_SLB_Region
  query=$query'&ServerCertificate='$ca_cert
  query=$query'&ServerCertificateName='$(_date)
  query=$query'&Format=json'
  query=$query'&PrivateKey='$ca_key
  query=$query'&SignatureMethod=HMAC-SHA1'
  query=$query'&Timestamp='$(_timestamp)
  query=$query'&SignatureVersion=1.0'
  query=$query'&SignatureNonce='$(_ali_nonce)
  query=$query'AccessKeyId='$Ali_Api_Key
  query=$query'&Version=2014-05-15'
}

#_add_slb_ca_query "$_ckey" "$_cfullchain"
_set_slb_server_certificate() {
  ca_key=$(_readfile "$1")
  ca_cert=$(_readfile "$2")
  query=''
  query=$query'&Action=SetLoadBalancerHTTPSListenerAttribute'
  query=$query'&RegionId='$Ali_SLB_Region
  query=$query'LoadBalancerId=lb-t4nj5vuz8ish9emfk1f20'
  query=$query'ListenerPort=443'
  query=$query'ServerCertificateId=1231579085529123_15dbf6ff26f_1991415478_2054196746'
  query=$query'Bandwidth=-1'
  query=$query'StickySession=on'
  query=$query'StickySessionType=insert'
  query=$query'HealthCheck=on'
  query=$query'&Version=2014-05-15'
  query=$query'AccessKeyId='$Ali_Api_Key
  query=$query'&SignatureMethod=HMAC-SHA1'
  query=$query'&Timestamp='$(_timestamp)
  query=$query'&SignatureVersion=1.0'
  query=$query'&SignatureNonce='$(_ali_nonce)
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