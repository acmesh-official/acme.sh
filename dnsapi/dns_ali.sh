#!/usr/bin/env bash

Ali_API='https://alidns.aliyuncs.com/'

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

  _check_exist_query "$_domain" "$_sub_domain"

  _rest

  record_id=$(_process_check_result)

  if [ $record_id == 0 ]; then
    #Add
    _add_record_query "$_domain" "$_sub_domain" "$txtvalue"
  else
    #Update
    _update_record_query "$record_id" "$_sub_domain" "$txtvalue"
  fi

  _rest

  echo $response

  return 0
}


dns_ali_rm() {
  fulldomain=$1
}

####################  Private functions bellow ##################################

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

    _describe_records_query $h
    if ! _rest; then
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

_rest() {
  signature=$(_sign $query)
  signature=$(_urlencode $signature)
  url= ${Ali_API}?${query}'&Signature='$signature

  response="$(_get "$url")"

  if [ "$?" != "0" ]; then
    _err "error!"
    return 1
  fi
  _debug2 response "$response"
  return 0
}

_urlencode() {
  python -c "import sys, urllib as ul;print ul.quote_plus('$1')"
}


_check_exist_query() {
  query=''
  query=$query'AccessKeyId='$Ali_Key
  query=$query'&Action=DescribeDomainRecords'
  query=$query'&DomainName='$1
  query=$query'&Format=json'
  query=$query'&RRKeyWord='$2
  query=$query'&SignatureMethod=HMAC-SHA1'
  query=$query'&SignatureNonce='$RANDOM
  query=$query'&SignatureVersion=1.0'
  query=$query'&Timestamp='$(_time)
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
  query=$query'&SignatureNonce='$RANDOM
  query=$query'&SignatureVersion=1.0'
  query=$query'&Timestamp='$(_time)
  query=$query'&Type=TXT'
  query=$query'&Value='$3
  query=$query'&Version=2015-01-09'
}

_update_record_query() {
  query=''
  query=$query'AccessKeyId='$Ali_Key
  query=$query'&Action=UpdateDomainRecord'
  query=$query'&Format=json'
  query=$query'&RecordId='$1
  query=$query'&RR='$2
  query=$query'&SignatureMethod=HMAC-SHA1'
  query=$query'&SignatureNonce='$RANDOM
  query=$query'&SignatureVersion=1.0'
  query=$query'&Timestamp='$(_time)
  query=$query'&Type=TXT'
  query=$query'&Value='$3
  query=$query'&Version=2015-01-09'
}

_describe_records_query() {
  query=''
  query=$query'AccessKeyId='$Ali_Key
  query=$query'&Action=DescribeDomainRecords'
  query=$query'&DomainName='$1
  query=$query'&Format=json'
  query=$query'&SignatureMethod=HMAC-SHA1'
  query=$query'&SignatureNonce='$RANDOM
  query=$query'&SignatureVersion=1.0'
  query=$query'&Timestamp='$(_time)
  query=$query'&Version=2015-01-09'
}

_time() {
  zone=$(date +%Z)
  sec=$(date +%s)
  t=$(date -d "1970-01-01 $zone $sec sec" +%Y-%m-%dT%H:%M:%SZ)
  t=$(_urlencode $t)
  echo $t
}

_sign() {
  StringToSign='GET&'$(_urlencode '/')'&'
  StringToSign=$StringToSign$(_urlencode  $1)
  echo -n  $StringToSign | openssl sha1 -hmac $Ali_Secret'&' -binary | openssl base64
}

_process_check_result() {
  python -c \
    "
import json;
result=json.loads('$response');
if result.has_key('Message'):
  print(result['Message']);
  quit(1);
records=result['DomainRecords']['Record'];
for r in result['DomainRecords']['Record']:
  if r['RR'] == '_acme-challenge.passport':
    print(r['RecordId']);
    quit();
print(0);
"
}
