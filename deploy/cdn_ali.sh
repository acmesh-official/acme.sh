#!/usr/bin/env sh

Alicdn_API="https://cdn.aliyuncs.com/"

#DEPLOY_CDN_Ali_Key=""
#DEPLOY_CDN_Ali_Secret=""
#DEPLOY_CDN_Ali_Prefix=""

########  Public functions #####################

#domain keyfile certfile cafile fullchain

cdn_ali_deploy() {
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

  DEPLOY_CDN_Ali_Key="${DEPLOY_CDN_Ali_Key:-$(_readdomainconf DEPLOY_CDN_Ali_Key)}"
  DEPLOY_CDN_Ali_Secret="${DEPLOY_CDN_Ali_Secret:-$(_readdomainconf DEPLOY_CDN_Ali_Secret)}"
  DEPLOY_CDN_Ali_Prefix="${DEPLOY_CDN_Ali_Prefix:-$(_readdomainconf DEPLOY_CDN_Ali_Prefix)}"
  if [ -z "$DEPLOY_CDN_Ali_Key" ] || [ -z "$DEPLOY_CDN_Ali_Secret" ]; then
    DEPLOY_CDN_Ali_Key=""
    DEPLOY_CDN_Ali_Secret=""
    _err "You don't specify alicdn api key and secret yet."
    return 1
  fi

  #save the api key and secret to the account conf file.
  _savedomainconf DEPLOY_CDN_Ali_Key "$DEPLOY_CDN_Ali_Key"
  _savedomainconf DEPLOY_CDN_Ali_Secret "$DEPLOY_CDN_Ali_Secret"
  _savedomainconf DEPLOY_CDN_Ali_Prefix "$DEPLOY_CDN_Ali_Prefix"

  # read cert and key files and urlencode both
  _certnamestr=$DEPLOY_CDN_Ali_Prefix$_cdomain'-'$(sha1sum "$_ccert" | cut -c1-20)
  _certtext=$(cat "$_cfullchain" | sed '/^$/d')
  _keytext=$(cat "$_ckey" | sed '/^$/d')
  _certstr=$(_urlencode "$_certtext")
  _keystr=$(_urlencode "$_keytext")

  _debug _certname "$_certnamestr"
  _debug2 _cert "$_certstr"
  _debug2 _key "$_keystr"

  _debug "Set Cert"
  _set_cert_query $(_urlencode "$DEPLOY_CDN_Ali_Prefix$_cdomain") $(_urlencode "$_certnamestr") "$_certstr" "$_keystr" && _ali_rest "Set Cert"
  return 0
}

########  Private functions #####################

_set_cert_query() {
  query=''
  query=$query'AccessKeyId='$DEPLOY_CDN_Ali_Key
  query=$query'&Action=SetDomainServerCertificate'
  query=$query'&CertName='$2
  query=$query'&DomainName='$1
  query=$query'&Format=json'
  query=$query'&PrivateKey='$4
  query=$query'&ServerCertificate='$3
  query=$query'&ServerCertificateStatus=on'
  query=$query'&SignatureMethod=HMAC-SHA1'
  query=$query"&SignatureNonce=$(_ali_nonce)"
  query=$query'&SignatureVersion=1.0'
  query=$query'&Timestamp='$(_timestamp)
  query=$query'&Version=2014-11-11'

  _debug2 query "$query"
}

_ali_rest() {
  signature=$(printf "%s" "GET&%2F&$(_ali_urlencode "$query")" | _hmac "sha1" "$(printf "%s" "$DEPLOY_CDN_Ali_Secret&" | _hex_dump | tr -d " ")" | _base64)
  signature=$(_ali_urlencode "$signature")
  url="$Alicdn_API?$query&Signature=$signature"

  if ! response="$(_get "$url")"; then
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

_ali_urlencode() {
  _str="$1"
  _str_len=${#_str}
  _u_i=1
  while [ "$_u_i" -le "$_str_len" ]; do
    _str_c="$(printf "%s" "$_str" | cut -c "$_u_i")"
    case $_str_c in [a-zA-Z0-9.~_-])
      printf "%s" "$_str_c"
      ;;
    *)
      printf "%%%02X" "'$_str_c"
      ;;
    esac
    _u_i="$(_math "$_u_i" + 1)"
  done
}

_ali_nonce() {
  #_head_n 1 </dev/urandom | _digest "sha256" hex | cut -c 1-31
  #Not so good...
  date +"%s%N"
}

_timestamp() {
  date -u +"%Y-%m-%dT%H%%3A%M%%3A%SZ"
}

_urlencode() {
  # urlencode <string>
  old_lc_collate=$LC_COLLATE
  LC_COLLATE=C
  local length="${#1}"
  for (( i = 0; i < length; i++ )); do
    local c="${1:i:1}"
    case $c in
      [a-zA-Z0-9.~_-]) printf "$c" ;;
    *) printf '%%%02X' "'$c" ;;
    esac
  done
  LC_COLLATE=$old_lc_collate
}
