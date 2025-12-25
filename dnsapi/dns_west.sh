#!/usr/bin/env sh
# -*- mode: sh; tab-width: 2; indent-tabs-mode: s; coding: utf-8 -*-

# This is the west.cn api v2.0 wrapper for acme.sh
# Author: riubin@qq.com
# Version: 0.0.2
# Created: 2022-10-30
# Updated: 2022-11-02
#
#     export DWEST_USERNAME="your username"
#     export DWEST_PASSWORD="your api password not acount password"
#
# Usage:
#     acme.sh --issue --dns dns_west -d example.com

DWEST_API_URL="https://api.west.cn/api/v2"

########  Public functions #####################
# Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_west_add() {
  fulldomain=$1
  txtvalue=$2
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"
  DWEST_USERNAME="${DWEST_USERNAME:-$(_readaccountconf_mutable DWEST_USERNAME)}"
  DWEST_PASSWORD="${DWEST_PASSWORD:-$(_readaccountconf_mutable DWEST_PASSWORD)}"

  if [ -z "$DWEST_USERNAME" ] || [ -z "$DWEST_PASSWORD" ]; then
    DWEST_USERNAME=""
    DWEST_PASSWORD=""
    _err "You didn't specify a west.cn account name or api password yet."
    _err "You can get yours from here https://www.west.cn/manager/API/APIconfig.asp"
    return 1
  fi

  # save the username and api password to the account conf file.
  _saveaccountconf_mutable DWEST_USERNAME "$DWEST_USERNAME"
  _saveaccountconf_mutable DWEST_PASSWORD "$DWEST_PASSWORD"

  _domain=$(expr "$fulldomain" : ".*\.\(.*\..*\)")
  _host=$(expr "$fulldomain" : '\(.*\)\..*\..*')
  _debug _domain "$_domain"
  _debug _host "$_host"

  
  if ! _dns_west_records "$_domain" "$_host"; then
    return 1
  fi
  _debug _host_records "$_host_records"

  # if record type is not TXT,delete it
  _none_txt_record_id=$(echo "$_host_records" | grep -v "$(printf '\tTXT')" |cut -f1)
  if [ -n "$_none_txt_record_id" ]; then
    if ! _dns_west_post "domain=${_domain}&id=${_none_txt_record_id}" "/domain/?act=deldnsrecord"; then
      _err "Delete record error."
      return 1
    fi
  fi
  # will return ok when the txtvalue exists
  _host_id=$(echo "$_host_records" | grep "$(printf '\t')$txtvalue" | cut -f1)
  _debug _host_id "$_host_id"

  if [ -n "$_host_id" ]; then
    _info "Already exists, OK"
    return 0
  fi

  # will add txt record  
  if ! _dns_west_post "domain=${_domain}&host=${_host}&type=TXT&value=${txtvalue}&ttl=60&level=10" "/domain/?act=adddnsrecord"; then
    _err "Add txt record error."
    return 1
  fi
  _info "Added, OK"
  _info "Sleep 30sec"
  sleep 30
  return 0
}

# Usage: rm  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_west_rm() {
  fulldomain=$1
  txtvalue=$2

  DWEST_USERNAME="${DWEST_USERNAME:-$(_readaccountconf_mutable DWEST_USERNAME)}"
  DWEST_PASSWORD="${DWEST_PASSWORD:-$(_readaccountconf_mutable DWEST_PASSWORD)}"

  _domain=$(expr "$fulldomain" : ".*\.\(.*\..*\)")
  _host=$(expr "$fulldomain" : "\(.*\)\..*\..*")
  _debug _domain "$_domain"
  _debug _host "$_host"
  # get domain records if the host already exists will return the host's id and value
  
  if ! _dns_west_records "$_domain" "$_host"; then
    return 1
  fi
  _debug _host_records "$_host_records"

  if [ -z "$_host_records" ]; then
    _info "Don't need to remove."
    return 0
  fi

  _host_id=$(echo "$_host_records" | grep "$(printf '\t')$txtvalue" | cut -f1)
  _debug _host_id "$_host_id"

  if [ -z "$_host_id" ]; then
    _info "Don't need to remove."
    return 0
  fi

  
  if ! _dns_west_post "domain=${_domain}&id=${_host_id}" "/domain/?act=deldnsrecord"; then
    _err " Delete record error."
    return 1
  fi
  _info "Deleted record, OK"
  return 0
}

####################  Private functions below ##################################
# Usage: _dns_west_records <domain.com> <_acme-challenge.www>
# because the TXT records can be more than one,so get domain records by host will return the more records rows,like:
#   {"id":113046690,"item":"_acme-challenge","value":"XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs","type":"TXT"...}
#   {"id":103790839,"item":"_acme-challenge","value":"x2mbcaewb52890s8fht2lcpts5w74a1pfq44q1hnmu1","type":"TXT"...}
# we only need id,value,type,so this function will store records to _host_records inform of <id \t value \t type> each line in stdout,like
#   113046690	XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs	TXT
#   103790839	x2mbcaewb52890s8fht2lcpts5w74a1pfq44q1hnmu1	TXT
# so you can simply use grep and cut to get some data form it
_dns_west_records() {
  _domain=$1
  _host=$2
  _value=$3
  _dns_west_post "limit=100&domain=${_domain}" "/domain/?act=getdnsrecord"
  if ! _dns_west_msg "$response"; then
    _err "error: " "$_error"
    return 1
  fi
  _host_records=$(printf "%s" "$response" | sed 's/{/&\n/g'|grep "$_host" | sed -n 's/.*\"id\"\:\([0-9]*\).*\"value\"\:\"\([^\"]*\)\",\"type\":\"\([^\"]*\)\".*/\1\t\2\t\3/p')
  return 0
}

# Usage: _dns_west_post <post data url encoded> <path start with '/'>
# returns:
#  response={}
_dns_west_post() {
  body=$1
  ep=$2
  _time_in_millisecond=$(($(date +%s%N)/1000000))

  _token=$(printf "%s" "$DWEST_USERNAME$DWEST_PASSWORD$_time_in_millisecond" | md5sum |cut -d ' ' -f1)
  _debug "create token" "$_token"

  _common_params="username=$DWEST_USERNAME&time=$_time_in_millisecond&token=$_token"
  _debug "common params" "$_common_params"

  _debug body "$body"
  _debug path "$ep"
  # west.cn api use gbk encode,so response must convert gbk to utf-8
  # post body didn't convert to gbk because the data content is english at all,so it don't need to convert
  response="$(_post "$_common_params&$body" "$DWEST_API_URL$ep" "" POST "application/x-www-form-urlencoded" | iconv -f GBK -t UTF-8)"
  if ! _dns_west_msg "$response"; then
    _err "error $ep" "$_error"
    return 1
  fi
  _debug2 response "$response"
  return 0
}

# Usage: _dns_west_msg response
# returns:
#  msg
_dns_west_msg(){
  _result=$(expr "$1" : '.*result\"\:\([0-9]*\)')
  if [ "$_result" != "200" ]; then
    _error=$(printf "%s" "$1" sed -n 's/.*msg\"\:\"\(\[^\"\]*\)\".*/\1/p')
    return 1
  fi
  return 0
}
