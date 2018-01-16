#!/usr/bin/env sh
# -*- mode: sh; tab-width: 2; indent-tabs-mode: s; coding: utf-8 -*-

# This is the InternetX autoDNS xml api wrapper for acme.sh
# Author: auerswald@gmail.com
# Created: 2018-01-14
#
#     export AUTODNS_USER="username"
#     export AUTODNS_PASSWORD="password"
#     export AUTODNS_CONTEXT="context"
#
# Usage:
#     acme.sh --issue --dns dns_autodns -d example.com

AUTODNS_API="https://gateway.autodns.com"

# Arguments:
#   txtdomain
#   txt
dns_autodns_add() {
  fulldomain="$1"
  txtvalue="$2"

  AUTODNS_USER="${AUTODNS_USER:-$(_readaccountconf_mutable AUTODNS_USER)}"
  AUTODNS_PASSWORD="${AUTODNS_PASSWORD:-$(_readaccountconf_mutable AUTODNS_PASSWORD)}"
  AUTODNS_CONTEXT="${AUTODNS_CONTEXT:-$(_readaccountconf_mutable AUTODNS_CONTEXT)}"

  if [ -z "$AUTODNS_USER" ] || [ -z "$AUTODNS_CONTEXT" ] || [ -z "$AUTODNS_PASSWORD" ]; then
    _err "You don't specify autodns user, password and context."
    return 1
  fi

  _saveaccountconf_mutable AUTODNS_USER "$AUTODNS_USER"
  _saveaccountconf_mutable AUTODNS_PASSWORD "$AUTODNS_PASSWORD"
  _saveaccountconf_mutable AUTODNS_CONTEXT "$AUTODNS_CONTEXT"

  _debug "First detect the root zone"

  if ! _get_autodns_zone "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _sub_domain "$_sub_domain"
  _debug _zone "$_zone"
  _debug _system_ns "$_system_ns"

  _info "Adding TXT record"

  autodns_response="$(_autodns_zone_update "$_zone" "$_sub_domain" "$txtvalue" "$_system_ns")"

  if [ "$?" -eq "0" ]; then
    _info "Added, OK"
    return 0
  fi

  return 1
}

# Arguments:
#   txtdomain
#   txt
dns_autodns_rm() {
  fulldomain="$1"
  txtvalue="$2"

  AUTODNS_USER="${AUTODNS_USER:-$(_readaccountconf_mutable AUTODNS_USER)}"
  AUTODNS_PASSWORD="${AUTODNS_PASSWORD:-$(_readaccountconf_mutable AUTODNS_PASSWORD)}"
  AUTODNS_CONTEXT="${AUTODNS_CONTEXT:-$(_readaccountconf_mutable AUTODNS_CONTEXT)}"

  if [ -z "$AUTODNS_USER" ] || [ -z "$AUTODNS_CONTEXT" ] || [ -z "$AUTODNS_PASSWORD" ]; then
    _err "You don't specify autodns user, password and context."
    return 1
  fi

  _debug "First detect the root zone"

  if ! _get_autodns_zone "$fulldomain"; then
    _err "zone not found"
    return 1
  fi

  _debug _sub_domain "$_sub_domain"
  _debug _zone "$_zone"
  _debug _system_ns "$_system_ns"

  _info "Delete TXT record"

  autodns_response="$(_autodns_zone_cleanup "$_zone" "$_sub_domain" "$txtvalue" "$_system_ns")"

  if [ "$?" -eq "0" ]; then
    _info "Deleted, OK"
    return 0
  fi

  return 1
}

####################  Private functions below ##################################

# Arguments:
#   fulldomain
# Returns:
#   _sub_domain=_acme-challenge.www
#   _zone=domain.com
#   _system_ns
_get_autodns_zone() {
  domain="$1"

  i=2
  p=1

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug h "$h"

    if [ -z "$h" ]; then
      # not valid
      return 1
    fi

    autodns_response="$(_autodns_zone_inquire "$h")"

    if [ "$?" -ne "0" ]; then
      _err "invalid domain"
      return 1
    fi

    if _contains "$autodns_response" "<summary>1</summary>" >/dev/null; then
      _zone="$(echo "$autodns_response" | _egrep_o '<name>[^<]*</name>' | cut -d '>' -f 2 | cut -d '<' -f 1)"
      _system_ns="$(echo "$autodns_response" | _egrep_o '<system_ns>[^<]*</system_ns>' | cut -d '>' -f 2 | cut -d '<' -f 1)"
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
      return 0
    fi

    p=$i
    i=$(_math "$i" + 1)
  done

  return 1
}

_build_request_auth_xml() {
  printf "<auth>
    <user>%s</user>
    <password>%s</password>
    <context>%s</context>
  </auth>" "$AUTODNS_USER" "$AUTODNS_PASSWORD" "$AUTODNS_CONTEXT"
}

# Arguments:
#   zone
_build_zone_inquire_xml() {
  printf "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
  <request>
    %s
    <task>
      <code>0205</code>
      <view>
        <children>1</children>
        <limit>1</limit>
      </view>
      <where>
        <key>name</key>
        <operator>eq</operator>
        <value>%s</value>
      </where>
    </task>
  </request>" "$(_build_request_auth_xml)" "$1"
}

# Arguments:
#   zone
#   subdomain
#   txtvalue
#   system_ns
_build_zone_update_xml() {
  printf "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
  <request>
    %s
    <task>
      <code>0202001</code>
      <default>
        <rr_add>
          <name>%s</name>
          <ttl>600</ttl>
          <type>TXT</type>
          <value>%s</value>
        </rr_add>
      </default>
      <zone>
        <name>%s</name>
        <system_ns>%s</system_ns>
      </zone>
    </task>
  </request>" "$(_build_request_auth_xml)" "$2" "$3" "$1" "$4"
}

# Arguments:
#   zone
_autodns_zone_inquire() {
  request_data="$(_build_zone_inquire_xml "$1")"
  autodns_response="$(_autodns_api_call "$request_data")"
  ret="$?"

  printf "%s" "$autodns_response"
  return "$ret"
}

# Arguments:
#   zone
#   subdomain
#   txtvalue
#   system_ns
_autodns_zone_update() {
  request_data="$(_build_zone_update_xml "$1" "$2" "$3" "$4")"
  autodns_response="$(_autodns_api_call "$request_data")"
  ret="$?"

  printf "%s" "$autodns_response"
  return "$ret"
}

# Arguments:
#   zone
#   subdomain
#   txtvalue
#   system_ns
_autodns_zone_cleanup() {
  request_data="$(_build_zone_update_xml "$1" "$2" "$3" "$4")"
  # replace 'rr_add>' with 'rr_rem>' in request_data
  request_data="$(printf -- "%s" "$request_data" | sed 's/rr_add>/rr_rem>/g')"
  autodns_response="$(_autodns_api_call "$request_data")"
  ret="$?"

  printf "%s" "$autodns_response"
  return "$ret"
}

# Arguments:
#   request_data
_autodns_api_call() {
  request_data="$1"

  _debug request_data "$request_data"

  autodns_response="$(_post "$request_data" "$AUTODNS_API")"
  ret="$?"

  _debug autodns_response "$autodns_response"

  if [ "$ret" -ne "0" ]; then
    _err "error"
    return 1
  fi

  if _contains "$autodns_response" "<type>success</type>" >/dev/null; then
    _info "success"
    printf "%s" "$autodns_response"
    return 0
  fi

  return 1
}
