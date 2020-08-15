#!/usr/bin/env sh

########################################################################
# Hurricane Electric hook script for acme.sh
#
# Environment variables:
#
#  - $HE_Username  (your dns.he.net username)
#  - $HE_Password  (your dns.he.net password)
#
# Author: Ondrej Simek <me@ondrejsimek.com>
# Git repo: https://github.com/angel333/acme.sh

#-- dns_he_add() - Add TXT record --------------------------------------
# Usage: dns_he_add _acme-challenge.subdomain.domain.com "XyZ123..."

dns_he_add() {
  _full_domain=$1
  _txt_value=$2
  _info "Using DNS-01 Hurricane Electric hook"

  HE_Username="${HE_Username:-$(_readaccountconf_mutable HE_Username)}"
  HE_Password="${HE_Password:-$(_readaccountconf_mutable HE_Password)}"
  if [ -z "$HE_Username" ] || [ -z "$HE_Password" ]; then
    HE_Username=
    HE_Password=
    _err "No auth details provided. Please set user credentials using the \$HE_Username and \$HE_Password environment variables."
    return 1
  fi
  _saveaccountconf_mutable HE_Username "$HE_Username"
  _saveaccountconf_mutable HE_Password "$HE_Password"

  # Fills in the $_zone_id
  _find_zone "$_full_domain" || return 1
  _debug "Zone id \"$_zone_id\" will be used."
  username_encoded="$(printf "%s" "${HE_Username}" | _url_encode)"
  password_encoded="$(printf "%s" "${HE_Password}" | _url_encode)"
  body="email=${username_encoded}&pass=${password_encoded}"
  body="$body&account="
  body="$body&menu=edit_zone"
  body="$body&Type=TXT"
  body="$body&hosted_dns_zoneid=$_zone_id"
  body="$body&hosted_dns_recordid="
  body="$body&hosted_dns_editzone=1"
  body="$body&Priority="
  body="$body&Name=$_full_domain"
  body="$body&Content=$_txt_value"
  body="$body&TTL=300"
  body="$body&hosted_dns_editrecord=Submit"
  response="$(_post "$body" "https://dns.he.net/")"
  exit_code="$?"
  if [ "$exit_code" -eq 0 ]; then
    _info "TXT record added successfully."
  else
    _err "Couldn't add the TXT record."
  fi
  _debug2 response "$response"
  return "$exit_code"
}

#-- dns_he_rm() - Remove TXT record ------------------------------------
# Usage: dns_he_rm _acme-challenge.subdomain.domain.com "XyZ123..."

dns_he_rm() {
  _full_domain=$1
  _txt_value=$2
  _info "Cleaning up after DNS-01 Hurricane Electric hook"
  HE_Username="${HE_Username:-$(_readaccountconf_mutable HE_Username)}"
  HE_Password="${HE_Password:-$(_readaccountconf_mutable HE_Password)}"
  # fills in the $_zone_id
  _find_zone "$_full_domain" || return 1
  _debug "Zone id \"$_zone_id\" will be used."

  # Find the record id to clean
  username_encoded="$(printf "%s" "${HE_Username}" | _url_encode)"
  password_encoded="$(printf "%s" "${HE_Password}" | _url_encode)"
  body="email=${username_encoded}&pass=${password_encoded}"
  body="$body&hosted_dns_zoneid=$_zone_id"
  body="$body&menu=edit_zone"
  body="$body&hosted_dns_editzone="

  response="$(_post "$body" "https://dns.he.net/")"
  _debug2 "response" "$response"
  if ! _contains "$response" "$_txt_value"; then
    _debug "The txt record is not found, just skip"
    return 0
  fi
  _record_id="$(echo "$response" | tr -d "#" | sed "s/<tr/#<tr/g" | tr -d "\n" | tr "#" "\n" | grep "$_full_domain" | grep '"dns_tr"' | grep "$_txt_value" | cut -d '"' -f 4)"
  _debug2 _record_id "$_record_id"
  if [ -z "$_record_id" ]; then
    _err "Can not find record id"
    return 1
  fi
  # Remove the record
  username_encoded="$(printf "%s" "${HE_Username}" | _url_encode)"
  password_encoded="$(printf "%s" "${HE_Password}" | _url_encode)"
  body="email=${username_encoded}&pass=${password_encoded}"
  body="$body&menu=edit_zone"
  body="$body&hosted_dns_zoneid=$_zone_id"
  body="$body&hosted_dns_recordid=$_record_id"
  body="$body&hosted_dns_editzone=1"
  body="$body&hosted_dns_delrecord=1"
  body="$body&hosted_dns_delconfirm=delete"
  _post "$body" "https://dns.he.net/" \
    | grep '<div id="dns_status" onClick="hideThis(this);">Successfully removed record.</div>' \
      >/dev/null
  exit_code="$?"
  if [ "$exit_code" -eq 0 ]; then
    _info "Record removed successfully."
  else
    _err "Could not clean (remove) up the record. Please go to HE administration interface and clean it by hand."
    return "$exit_code"
  fi
}

########################## PRIVATE FUNCTIONS ###########################

_find_zone() {
  _domain="$1"
  username_encoded="$(printf "%s" "${HE_Username}" | _url_encode)"
  password_encoded="$(printf "%s" "${HE_Password}" | _url_encode)"
  body="email=${username_encoded}&pass=${password_encoded}"
  response="$(_post "$body" "https://dns.he.net/")"
  _debug2 response "$response"
  if _contains "$response" '>Incorrect<'; then
    _err "Unable to login to dns.he.net please check username and password"
    return 1
  fi
  _table="$(echo "$response" | tr -d "#" | sed "s/<table/#<table/g" | tr -d "\n" | tr "#" "\n" | grep 'id="domains_table"')"
  _debug2 _table "$_table"
  _matches="$(echo "$_table" | sed "s/<tr/#<tr/g" | tr "#" "\n" | grep 'alt="edit"' | tr -d " " | sed "s/<td/#<td/g" | tr "#" "\n" | grep 'hosted_dns_zoneid')"
  _debug2 _matches "$_matches"
  # Zone names and zone IDs are in same order
  _zone_ids=$(echo "$_matches" | _egrep_o "hosted_dns_zoneid=[0-9]*&" | cut -d = -f 2 | tr -d '&')
  _zone_names=$(echo "$_matches" | _egrep_o "name=.*onclick" | cut -d '"' -f 2)
  _debug2 "These are the zones on this HE account:"
  _debug2 "_zone_names" "$_zone_names"
  _debug2 "And these are their respective IDs:"
  _debug2 "_zone_ids" "$_zone_ids"
  if [ -z "$_zone_names" ] || [ -z "$_zone_ids" ]; then
    _err "Can not get zone names."
    return 1
  fi
  # Walk through all possible zone names
  _strip_counter=1
  while true; do
    _attempted_zone=$(echo "$_domain" | cut -d . -f ${_strip_counter}-)

    # All possible zone names have been tried
    if [ -z "$_attempted_zone" ]; then
      _err "No zone for domain \"$_domain\" found."
      return 1
    fi

    _debug "Looking for zone \"${_attempted_zone}\""

    line_num="$(echo "$_zone_names" | grep -n "^$_attempted_zone\$" | _head_n 1 | cut -d : -f 1)"
    _debug2 line_num "$line_num"
    if [ "$line_num" ]; then
      _zone_id=$(echo "$_zone_ids" | sed -n "${line_num}p")
      if [ -z "$_zone_id" ]; then
        _err "Can not find zone id."
        return 1
      fi
      _debug "Found relevant zone \"$_attempted_zone\" with id \"$_zone_id\" - will be used for domain \"$_domain\"."
      return 0
    fi

    _debug "Zone \"$_attempted_zone\" doesn't exist, let's try a less specific zone."
    _strip_counter=$(_math "$_strip_counter" + 1)
  done
}
# vim: et:ts=2:sw=2:
