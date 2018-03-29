#!/usr/bin/env sh

Ali_API="https://alidns.aliyuncs.com/"
api_version="2015-01-09"

. "${LE_WORKING_DIR}/libs/aliyun.sh"

#Ali_Key="LTqIA87hOKdjevsf5"
#Ali_Secret="0p5EYueFNq501xnCPzKNbx6K51qPH2"

#Usage: dns_ali_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_ali_add() {
  fulldomain="$1"
  txtvalue="$2"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    return 1
  fi

  _debug "Add record"
  _add_record_query "$_domain" "$_sub_domain" "$txtvalue" && ali_rest $Ali_API "Add record"
}

dns_ali_rm() {
  fulldomain="$1"
  txtvalue="$2"
  Ali_Key="${Ali_Key:-$(_readaccountconf_mutable Ali_Key)}"
  Ali_Secret="${Ali_Secret:-$(_readaccountconf_mutable Ali_Secret)}"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    return 1
  fi

  _clean
}

####################  Private functions below ##################################

_get_root() {
  domain="$"1
  i=2
  p=1
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    _describe_records_query "$h"
    if ! ali_rest $Ali_API "Get root" "ignore"; then
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

_check_exist_query() {
  _qdomain="$1"
  _qsubdomain="$2"

  ali_query_builder \
    Action=DescribeDomainRecords \
    "DomainName=$_qdomain" \
    "RRKeyWord=$_qsubdomain" \
    TypeKeyWord=TXT \
    "Version=$api_version"
}

_add_record_query() {
  ali_query_builder \
    Action=AddDomainRecord \
    "DomainName=$1" \
    "RR=$2" \
    Type=TXT \
    "Value=$3" \
    "Version=$api_version"
}

_delete_record_query() {
  ali_query_builder Action=DeleteDomainRecord \
    "RecordId=$1" \
    "Version=$api_version"
}

_describe_records_query() {
  ali_query_builder \
    Action=DescribeDomainRecords \
    "DomainName=$1" \
    "Version=$api_version"
}

_clean() {
  _check_exist_query "$_domain" "$_sub_domain"
  if ! ali_rest $Ali_API "Check exist records" "ignore"; then
    return 1
  fi

  record_id="$(echo "$response" | tr '{' "\n" | grep "$_sub_domain" | grep "$txtvalue" | tr "," "\n" | grep RecordId | cut -d '"' -f 4)"
  _debug2 record_id "$record_id"

  if [ -z "$record_id" ]; then
    _debug "record not found, skip"
  else
    _delete_record_query "$record_id"
    ali_rest $Ali_API "Delete record $record_id" "ignore"
  fi
}
