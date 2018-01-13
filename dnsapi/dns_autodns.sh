#!/usr/bin/env sh
# -*- mode: sh; tab-width: 2; indent-tabs-mode: s; coding: utf-8 -*-

# This is the InternetX autodns xml api wrapper for acme.sh

AUTODNS_API="https://gateway.autodns.com"

AUTODNS_USER="${AUTODNS_USER:-$(_readaccountconf_mutable AUTODNS_USER)}"
AUTODNS_CONTEXT="${AUTODNS_CONTEXT:-$(_readaccountconf_mutable AUTODNS_CONTEXT)}"
AUTODNS_PASSWORD="${AUTODNS_PASSWORD:-$(_readaccountconf_mutable AUTODNS_PASSWORD)}"

if [[ -z "$AUTODNS_USER" ]] || [[ -z "$AUTODNS_CONTEXT" ]] || [[ -z "$AUTODNS_PASSWORD" ]]; then
    _err "You don't specify autodns user, password and context."
    return 1
else
  _saveaccountconf_mutable AUTODNS_USER "$AUTODNS_USER"
  _saveaccountconf_mutable AUTODNS_CONTEXT "$AUTODNS_CONTEXT"
  _saveaccountconf_mutable AUTODNS_PASSWORD "$AUTODNS_PASSWORD"
fi

# Arguments:
#   fulldomain
#   txtvalue
# Globals:
#   _sub_domain
#   _domain
dns_autodns_add() {
  local fulldomain="$1"
  local txtvalue="$2"

  _debug "First detect the root zone"

  if ! _get_autodns_zone "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _info "Adding record"

  if _autodns_zone_update "$_domain" "$_sub_domain" "$txtvalue"; then
    _info "Added, OK"
    return 0
  fi

  return 1
}

# Arguments:
#   fulldomain
#   txtvalue
# Globals:
#   _sub_domain
#   _domain
dns_autodns_rm() {
  local fulldomain="$1"
  local txtvalue="$2"

  _debug "First detect the root zone"

  if ! _get_autodns_zone "$fulldomain"; then
    _err "zone not found"
    return 1
  fi

  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _info "Delete record"

  if _autodns_zone_cleanup "$_domain" "$_sub_domain" "$txtvalue"; then
    _info "Deleted, OK"
    return 0
  fi
}

####################  Private functions below ##################################

# Arguments:
#   fulldomain
# Returns:
#   _sub_domain=_acme-challenge.www
#   _domain=domain.com
_get_autodns_zone() {
  local domain="$1"
  local autodns_response

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

    if [[ "$?" -ne 0 ]]; then
      _err "invalid domain"
      return 1
    fi

    if _contains "$autodns_response" "<type>success</type>" >/dev/null; then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
      _domain=$h
      return 0
    else
      return 1
    fi

    p=$i
    i=$(_math "$i" + 1)
  done

  return 1
}

# Globals:
#   AUTODNS_USER
#   AUTODNS_PASSWORD
#   AUTODNS_CONTEXT
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
  local zone="$1"

  printf "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
  <request>
    %s
    <task>
      <code>0205</code>
      <zone>
        <name>%s</name>
      </zone>
    </task>
  </request>" "$(_build_request_auth_xml)" "$zone"
}

# Arguments:
#   zone
#   subdomain
#   txtvalue
_build_zone_update_xml() {
  local zone="$1"
  local subdomain="$2"
  local txtvalue="$3"

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
      </zone>
    </task>
  </request>" "$(_build_request_auth_xml)" "$subdomain" "$txtvalue" "$zone"
}

# Arguments:
#   zone
_autodns_zone_inquire() {
  local zone="$1"
  local request_data
  local autodns_response

  request_data="$(_build_zone_inquire_xml "$zone")"
  autodns_response="$(_autodns_api_call "$request_data")"

  printf "%s" "$autodns_response"
}

# Arguments:
#   zone
#   subdomain
#   txtvalue
_autodns_zone_update() {
  local zone="$1"
  local subdomain="$2"
  local txtvalue="$3"
  local request_data
  local autodns_response

  request_data="$(_build_zone_update_xml "$zone" "$subdomain" "$txtvalue")"
  autodns_response="$(_autodns_api_call "$request_data")"

  printf "%s" "$autodns_response"
}

# Arguments:
#   zone
#   subdomain
#   txtvalue
_autodns_zone_cleanup() {
  local zone="$1"
  local subdomain="$2"
  local txtvalue="$3"
  local request_data
  local autodns_response

  request_data="$(_build_zone_update_xml "$zone" "$subdomain" "$txtvalue")"
  # replace 'rr_add>' with 'rr_rem>' in request_data
  request_data="${request_data//rr_add>/rr_rem>}"
  autodns_response="$(_autodns_api_call "$request_data")"

  printf "%s" "$autodns_response"
}

# Arguments:
#   request_data
_autodns_api_call() {
  local request_data="$1"
  local autodns_response

  _debug request_data "$request_data"

  autodns_response="$(_post "$request_data" "$AUTODNS_API")"

  if [[ "$?" -ne 0 ]]; then
    _err "error"
    _debug autodns_response "$autodns_response"
    return 1
  fi

  if _contains "$autodns_response" "<type>success</type>" >/dev/null; then
    _info "success"
    _debug autodns_response "$autodns_response"
    printf "%s" "$autodns_response"
    return 0
  fi

  return 1
}
