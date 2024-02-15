#!/usr/bin/env sh

# Script to create certificate to Aliyun CDN
#
# This deployment required following variables
# export ALI_CDN_KEY="LTqIA87hOKdjevsf5"
# export ALI_CDN_SECRET="0p5EYueFNq501xnCPzKNbx6K51qPH2"
# export Ali_CDN_DOMAIN="cdn.example.com"
# If you have more than one domain, just
# export Ali_CDN_DOMAIN="cdn1.example.com,cdn2.example.com"
#
# If ALI_CDN_KEY and ALI_CDN_SECRET are not set,
# Ali_key and Ali_Secret will be used. (see dns/dns_ali.sh)
#
# AliYun Authentication must have "AliyunCDNFullAccess" permission,
# May also need to "AliyunYundunCertFullAccess" permissions.
#
# Thanks:
# This script references dns/dns_ali.sh and pull request #2772

########  Public functions #####################
Ali_CDN_API="https://cdn.aliyuncs.com/"

alicdn_deploy() {
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

  _info "$(__green "===Starting alicdn deploy===")"

  _getdeployconf ALI_CDN_KEY
  _getdeployconf ALI_CDN_SECRET
  _getdeployconf Ali_CDN_DOMAIN

  if [ -z "${ALI_CDN_KEY}" ] || [ -z "${ALI_CDN_SECRET}" ]; then
    _info "Not set variables ALI_CDN_KEY and ALI_CDN_SECRET"
    _info "Will use Ali_Key and Ali_Secret"
    ALI_CDN_KEY="$(_readaccountconf_mutable Ali_Key)"
    ALI_CDN_SECRET="$(_readaccountconf_mutable Ali_Secret)"
    if [ -z "${ALI_CDN_KEY}" ] || [ -z "${ALI_CDN_SECRET}" ]; then
      _err "You don't specify aliyun api key and secret yet."
      return 1
    fi
  else
    #save ALI_CDN_KEY and ALI_CDN_SECRET.
    _savedeployconf ALI_CDN_KEY "$ALI_CDN_KEY"
    _savedeployconf ALI_CDN_SECRET "$ALI_CDN_SECRET"
  fi

  if [ -z "${Ali_CDN_DOMAIN}" ]; then
    Ali_CDN_DOMAIN=""
    _err "You don't specify Ali_CDN_DOMAIN yet."
    return 1
  fi
  #save Ali_CDN_DOMAIN.
  _savedeployconf Ali_CDN_DOMAIN "$Ali_CDN_DOMAIN"

  _debug ALI_CDN_KEY "${ALI_CDN_KEY}"
  _debug ALI_CDN_SECRET "$ALI_CDN_SECRET"
  _debug Ali_CDN_DOMAIN "$Ali_CDN_DOMAIN"

  ## upload certificate
  _Ali_SSLPub=$(grep -Ev '^$' "$_cfullchain" | _ali_url_encode)
  _Ali_SSLPri=$(_ali_url_encode <"$_ckey")

  query=''
  query=$query'AccessKeyId='${ALI_CDN_KEY}
  query=$query'&Action=BatchSetCdnDomainServerCertificate'
  query=$query'&CertName='$(_ali_urlencode "$_cdomain")
  query=$query'&CertType=upload'
  query=$query'&DomainName='$(_ali_urlencode "$Ali_CDN_DOMAIN")
  query=$query'&ForceSet=1'
  query=$query'&Format=json'
  query=$query'&SSLPri='${_Ali_SSLPri}
  query=$query'&SSLProtocol=on'
  query=$query'&SSLPub='${_Ali_SSLPub}
  query=$query'&SignatureMethod=HMAC-SHA1'
  query=$query'&SignatureNonce='$(_ali_nonce)
  query=$query'&SignatureVersion=1.0'
  query=$query'&Timestamp='$(_timestamp)
  query=$query'&Version=2018-05-10'
  _debug2 signature_source "$(printf "%s" "GET&%2F&$(_ali_urlencode "$query")")"
  signature=$(printf "%s" "GET&%2F&$(_ali_urlencode "$query")" | _hmac "sha1" "$(printf "%s" "$ALI_CDN_SECRET&" | _hex_dump | tr -d " ")" | _base64)
  signature=$(_ali_urlencode "$signature")
  url="$Ali_CDN_API?$query&Signature=$signature"

  if ! response="$(_get "$url")"; then
    _err "Error <$1>"
    return 1
  fi
  _debug response "$response"
  message="$(echo "$response" | _egrep_o "\"Message\":\"[^\"]*\"" | cut -d : -f 2- | tr -d \")"
  if [ "$message" ]; then
    _err "$message"
    return 1
  fi
  _info "Domain $_cdomain certificate has been deployed successfully"
  _info "$(__green "===End alicdn deploy===")"
  return 0
}

####################  Private functions below ##################################
_ali_url_encode() {
  _hex_str=$(_hex_dump)
  _debug3 "_url_encode"
  _debug3 "_hex_str" "$_hex_str"
  for _hex_code in $_hex_str; do
    #upper case
    case "${_hex_code}" in
    "41")
      printf "%s" "A"
      ;;
    "42")
      printf "%s" "B"
      ;;
    "43")
      printf "%s" "C"
      ;;
    "44")
      printf "%s" "D"
      ;;
    "45")
      printf "%s" "E"
      ;;
    "46")
      printf "%s" "F"
      ;;
    "47")
      printf "%s" "G"
      ;;
    "48")
      printf "%s" "H"
      ;;
    "49")
      printf "%s" "I"
      ;;
    "4a")
      printf "%s" "J"
      ;;
    "4b")
      printf "%s" "K"
      ;;
    "4c")
      printf "%s" "L"
      ;;
    "4d")
      printf "%s" "M"
      ;;
    "4e")
      printf "%s" "N"
      ;;
    "4f")
      printf "%s" "O"
      ;;
    "50")
      printf "%s" "P"
      ;;
    "51")
      printf "%s" "Q"
      ;;
    "52")
      printf "%s" "R"
      ;;
    "53")
      printf "%s" "S"
      ;;
    "54")
      printf "%s" "T"
      ;;
    "55")
      printf "%s" "U"
      ;;
    "56")
      printf "%s" "V"
      ;;
    "57")
      printf "%s" "W"
      ;;
    "58")
      printf "%s" "X"
      ;;
    "59")
      printf "%s" "Y"
      ;;
    "5a")
      printf "%s" "Z"
      ;;

      #lower case
    "61")
      printf "%s" "a"
      ;;
    "62")
      printf "%s" "b"
      ;;
    "63")
      printf "%s" "c"
      ;;
    "64")
      printf "%s" "d"
      ;;
    "65")
      printf "%s" "e"
      ;;
    "66")
      printf "%s" "f"
      ;;
    "67")
      printf "%s" "g"
      ;;
    "68")
      printf "%s" "h"
      ;;
    "69")
      printf "%s" "i"
      ;;
    "6a")
      printf "%s" "j"
      ;;
    "6b")
      printf "%s" "k"
      ;;
    "6c")
      printf "%s" "l"
      ;;
    "6d")
      printf "%s" "m"
      ;;
    "6e")
      printf "%s" "n"
      ;;
    "6f")
      printf "%s" "o"
      ;;
    "70")
      printf "%s" "p"
      ;;
    "71")
      printf "%s" "q"
      ;;
    "72")
      printf "%s" "r"
      ;;
    "73")
      printf "%s" "s"
      ;;
    "74")
      printf "%s" "t"
      ;;
    "75")
      printf "%s" "u"
      ;;
    "76")
      printf "%s" "v"
      ;;
    "77")
      printf "%s" "w"
      ;;
    "78")
      printf "%s" "x"
      ;;
    "79")
      printf "%s" "y"
      ;;
    "7a")
      printf "%s" "z"
      ;;
      #numbers
    "30")
      printf "%s" "0"
      ;;
    "31")
      printf "%s" "1"
      ;;
    "32")
      printf "%s" "2"
      ;;
    "33")
      printf "%s" "3"
      ;;
    "34")
      printf "%s" "4"
      ;;
    "35")
      printf "%s" "5"
      ;;
    "36")
      printf "%s" "6"
      ;;
    "37")
      printf "%s" "7"
      ;;
    "38")
      printf "%s" "8"
      ;;
    "39")
      printf "%s" "9"
      ;;
    "2d")
      printf "%s" "-"
      ;;
    "5f")
      printf "%s" "_"
      ;;
    "2e")
      printf "%s" "."
      ;;
    "7e")
      printf "%s" "~"
      ;;
    #other hex
    *)
      printf '%%%s' "$_hex_code" | tr '[:lower:]' '[:upper:]'
      ;;
    esac
  done
}

_ali_urlencode() {
  _str=$(printf "%s" "$1" | _ali_url_encode)
  printf "%s" "$_str"
}

_ali_nonce() {
  date +"%s%N"
}

_timestamp() {
  date -u +"%Y-%m-%dT%H%%3A%M%%3A%SZ"
}
