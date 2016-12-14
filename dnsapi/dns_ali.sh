#!/usr/bin/env sh

Ali_API="https://alidns.aliyuncs.com/"

#Ali_Key="LTqIA87hOKdjevsf5"
#Ali_Secret="0p5EYueFNq501xnCPzKNbx6K51qPH2"

#Usage: dns_ali_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_ali_add() {
  fulldomain=$1
  txtvalue=$2

  if [ -z "$Ali_Key" ] || [ -z "$Ali_Secret" ]; then
    Ali_Key=""
    Ali_Secret=""
    _err "You don't specify aliyun api key and secret yet."
    return 1
  fi

  #save the api key and secret to the account conf file.
  _saveaccountconf Ali_Key "$Ali_Key"
  _saveaccountconf Ali_Secret "$Ali_Secret"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    return 1
  fi

  _debug "Add record"
  _add_record_query "$_domain" "$_sub_domain" "$txtvalue" && _ali_rest "Add record"
}

dns_ali_rm() {
  fulldomain=$1
  _clean
}

####################  Private functions below ##################################

_get_root() {
  domain=$1
  i=2
  p=1
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    _describe_records_query "$h"
    if ! _ali_rest "Get root" "ignore"; then
      return 1
    fi

    if _contains "$response" "PageNumber"; then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
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

_ali_rest() {
  signature=$(printf "%s" "GET&%2F&$(_ali_urlencode "$query")" | _hmac "sha1" "$(_hex "$Ali_Secret&")" | _base64)
  signature=$(_ali_urlencode "$signature")
  url="$Ali_API?$query&Signature=$signature"

  if ! response="$(_get "$url")"; then
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

  _debug2 response "$response"
  return 0
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

_check_exist_query() {
  query=''
  query=$query'AccessKeyId='$Ali_Key
  query=$query'&Action=DescribeDomainRecords'
  query=$query'&DomainName='$1
  query=$query'&Format=json'
  query=$query'&RRKeyWord=_acme-challenge'
  query=$query'&SignatureMethod=HMAC-SHA1'
  query=$query"&SignatureNonce=$(_ali_nonce)"
  query=$query'&SignatureVersion=1.0'
  query=$query'&Timestamp='$(_timestamp)
  query=$query'&TypeKeyWord=TXT'
  query=$query'&Version=2015-01-09'
}

_add_record_query() {
  query=''
  query=$query'AccessKeyId='$Ali_Key
  query=$query'&Action=AddDomainRecord'
  query=$query'&DomainName='$1
  query=$query'&Format=json'
  query=$query'&RR='$2
  query=$query'&SignatureMethod=HMAC-SHA1'
  query=$query"&SignatureNonce=$(_ali_nonce)"
  query=$query'&SignatureVersion=1.0'
  query=$query'&Timestamp='$(_timestamp)
  query=$query'&Type=TXT'
  query=$query'&Value='$3
  query=$query'&Version=2015-01-09'
}

_delete_record_query() {
  query=''
  query=$query'AccessKeyId='$Ali_Key
  query=$query'&Action=DeleteDomainRecord'
  query=$query'&Format=json'
  query=$query'&RecordId='$1
  query=$query'&SignatureMethod=HMAC-SHA1'
  query=$query"&SignatureNonce=$(_ali_nonce)"
  query=$query'&SignatureVersion=1.0'
  query=$query'&Timestamp='$(_timestamp)
  query=$query'&Version=2015-01-09'
}

_describe_records_query() {
  query=''
  query=$query'AccessKeyId='$Ali_Key
  query=$query'&Action=DescribeDomainRecords'
  query=$query'&DomainName='$1
  query=$query'&Format=json'
  query=$query'&SignatureMethod=HMAC-SHA1'
  query=$query"&SignatureNonce=$(_ali_nonce)"
  query=$query'&SignatureVersion=1.0'
  query=$query'&Timestamp='$(_timestamp)
  query=$query'&Version=2015-01-09'
}

_clean() {
  _check_exist_query "$_domain"
  if ! _ali_rest "Check exist records" "ignore"; then
    return 1
  fi

  records="$(echo "$response" -n | _egrep_o "\"RecordId\":\"[^\"]*\"" | cut -d : -f 2 | tr -d \")"
  printf "%s" "$records" \
    | while read -r record_id; do
      _delete_record_query "$record_id"
      _ali_rest "Delete record $record_id" "ignore"
    done
}

_timestamp() {
  date -u +"%Y-%m-%dT%H%%3A%M%%3A%SZ"
}
