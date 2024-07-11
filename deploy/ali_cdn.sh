#!/usr/bin/env sh

# Script to create certificate to Alibaba Cloud CDN
#
# This deployment required following variables
# export Ali_Key="ALIACCESSKEY"
# export Ali_Secret="ALISECRETKEY"
# export DEPLOY_ALI_CDN_DOMAIN="cdn.example.com"
# If you have more than one domain, just
# export DEPLOY_ALI_CDN_DOMAIN="cdn1.example.com cdn2.example.com"
#
# The credentials are shared with all domains, also shared with dns_ali api

Ali_API="https://cdn.aliyuncs.com/"

ali_cdn_deploy() {
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

  Ali_Key="${Ali_Key:-$(_readaccountconf_mutable Ali_Key)}"
  Ali_Secret="${Ali_Secret:-$(_readaccountconf_mutable Ali_Secret)}"
  if [ -z "$Ali_Key" ] || [ -z "$Ali_Secret" ]; then
    Ali_Key=""
    Ali_Secret=""
    _err "You don't specify aliyun api key and secret yet."
    return 1
  fi

  #save the api key and secret to the account conf file.
  _saveaccountconf_mutable Ali_Key "$Ali_Key"
  _saveaccountconf_mutable Ali_Secret "$Ali_Secret"

  _getdeployconf DEPLOY_ALI_CDN_DOMAIN
  if [ "$DEPLOY_ALI_CDN_DOMAIN" ]; then
    _savedeployconf DEPLOY_ALI_CDN_DOMAIN "$DEPLOY_ALI_CDN_DOMAIN"
  else
    DEPLOY_ALI_CDN_DOMAIN="$_cdomain"
  fi

  # read cert and key files and urlencode both
  _cert=$(_url_encode_upper <"$_cfullchain")
  _key=$(_url_encode_upper <"$_ckey")

  _debug2 _cert "$_cert"
  _debug2 _key "$_key"

  ## update domain ssl config
  for domain in $DEPLOY_ALI_CDN_DOMAIN; do
    _set_cdn_domain_ssl_certificate_query "$domain" "$_cert" "$_key"
    if _ali_rest "Set CDN domain SSL certificate for $domain" "" POST; then
      _info "Domain $domain certificate has been deployed successfully"
    fi
  done

  return 0
}

####################  Private functions below ##################################

# act ign mtd
_ali_rest() {
  act="$1"
  ign="$2"
  mtd="$3"

  signature=$(printf "%s" "$mtd&%2F&$(_ali_urlencode "$query")" | _hmac "sha1" "$(printf "%s" "$Ali_Secret&" | _hex_dump | tr -d " ")" | _base64)
  signature=$(_ali_urlencode "$signature")
  url="$Ali_API?$query&Signature=$signature"

  if [ "$mtd" = "GET" ]; then
    response="$(_get "$url")"
  else
    # post payload is not supported yet because of signature
    response="$(_post "" "$url")"
  fi

  _ret="$?"
  _debug2 response "$response"
  if [ "$_ret" != "0" ]; then
    _err "Error <$act>"
    return 1
  fi

  if [ -z "$ign" ]; then
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
  date +"%s%N" | sed 's/%N//g'
}

_timestamp() {
  date -u +"%Y-%m-%dT%H%%3A%M%%3A%SZ"
}

# stdin stdout
_url_encode_upper() {
  encoded=$(_url_encode)

  for match in $(echo "$encoded" | _egrep_o '%..' | sort -u); do
    upper=$(echo "$match" | _upper_case)
    encoded=$(echo "$encoded" | sed "s/$match/$upper/g")
  done

  echo "$encoded"
}

# domain pub pri
_set_cdn_domain_ssl_certificate_query() {
  query=''
  query=$query'AccessKeyId='$Ali_Key
  query=$query'&Action=SetCdnDomainSSLCertificate'
  query=$query'&CertType=upload'
  query=$query'&DomainName='$1
  query=$query'&Format=json'
  query=$query'&SSLPri='$3
  query=$query'&SSLProtocol=on'
  query=$query'&SSLPub='$2
  query=$query'&SignatureMethod=HMAC-SHA1'
  query=$query"&SignatureNonce=$(_ali_nonce)"
  query=$query'&SignatureVersion=1.0'
  query=$query'&Timestamp='$(_timestamp)
  query=$query'&Version=2018-05-10'
}
