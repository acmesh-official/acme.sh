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

  if [ -z "$HE_Username" ] || [ -z "$HE_Password" ]; then
    HE_Username=
    HE_Password=
    _err "No auth details provided. Please set user credentials using the \$HE_Username and \$HE_Password envoronment variables."
    return 1
  fi
  _saveaccountconf HE_Username "$HE_Username"
  _saveaccountconf HE_Password "$HE_Password"

  if [ ! -z "$HE_OTP_Secret" ]; then
    _saveaccountconf HE_OTP_Secret "$HE_OTP_Secret"
  else
    HE_OTP_Secret=
    _clearaccountconf HE_OTP_Secret
  fi

  if [ ! -z "$HE_OTP_Secret" ]; then
    _sign_in
  fi

  # Fills in the $_zone_id
  _find_zone "$_full_domain" || return 1
  _debug "Zone id \"$_zone_id\" will be used."

  if [ ! -z "$HE_OTP_Secret" ]; then
    body="account="
  else
    body="email=${HE_Username}&pass=${HE_Password}"
    body="$body&account="
  fi

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

  if [ ! -z "$HE_OTP_Secret" ]; then
    _sign_out
  fi

  return "$exit_code"
}

#-- dns_he_rm() - Remove TXT record ------------------------------------
# Usage: dns_he_rm _acme-challenge.subdomain.domain.com "XyZ123..."

dns_he_rm() {
  _full_domain=$1
  _txt_value=$2
  _info "Cleaning up after DNS-01 Hurricane Electric hook"

  if [ ! -z "$HE_OTP_Secret" ]; then
    _sign_in
  fi

  # fills in the $_zone_id
  _find_zone "$_full_domain" || return 1
  _debug "Zone id \"$_zone_id\" will be used."

  # Find the record id to clean
  if [ ! -z "$HE_OTP_Secret" ]; then
    body="hosted_dns_zoneid=$_zone_id"
  else
    body="email=${HE_Username}&pass=${HE_Password}"
    body="$body&hosted_dns_zoneid=$_zone_id"
  fi
  
  body="$body&menu=edit_zone"
  body="$body&hosted_dns_editzone="
  domain_regex="$(echo "$_full_domain" | sed 's/\./\\./g')" # escape dots
  _record_id=$(_post "$body" "https://dns.he.net/" \
    | tr -d '\n' \
    | _egrep_o "data=\"&quot;${_txt_value}&quot;([^>]+>){6}[^<]+<[^;]+;deleteRecord\('[0-9]+','${domain_regex}','TXT'\)" \
    | _egrep_o "[0-9]+','${domain_regex}','TXT'\)$" \
    | _egrep_o "^[0-9]+"
  )
  # The series of egreps above could have been done a bit shorter but
  #  I wanted to double-check whether it's the correct record (in case
  #  HE changes their website somehow).

  # Remove the record
  if [ ! -z "$HE_OTP_Secret" ]; then
    body="menu=edit_zone"
  else
    body="email=${HE_Username}&pass=${HE_Password}"
    body="$body&menu=edit_zone"
  fi
  
  body="menu=edit_zone"
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
    if [ ! -z "$HE_OTP_Secret" ]; then
      _sign_out
    fi
  else
    _err "Could not clean (remove) up the record. Please go to HE administration interface and clean it by hand."
    if [ ! -z "$HE_OTP_Secret" ]; then
      _sign_out
    fi
    return "$exit_code"
  fi
}

########################## PRIVATE FUNCTIONS ###########################

#-- _sign_in() ---------------------------------------------------------
# Signs into the Hurricane Electric account.
# This assumes cookies are usable and available.

_sign_in() {
  _debug "Signing into Hurricane Electric account."

  body="email=${HE_Username}&pass=${HE_Password}"

  response="$(_post "$body" "https://dns.he.net/")"

  # Check whether we're using an OTP code
  if [ ! -z "$HE_OTP_Secret" ]; then
    _debug "  - Using OTP code..."
    _saveaccountconf HE_OTP_Secret "$HE_OTP_Secret"

    if ! _exists oathtool; then
      _err "Please install oathtool to use 2 Factor Authentication."
      _err ""
      return 1
    fi

    otp_code="$(oathtool --base32 --totp "${HE_OTP_Secret}" 2>/dev/null)"
    body="tfacode=${otp_code}&submit=Submit"
    response="$(_post "$body" "https://dns.he.net/")"
  fi
}

#-- _sign_out() --------------------------------------------------------
# Signs out of the Hurricane Electric account.
# This assumes cookies are usable and available.

_sign_out() {
  _debug "Signing out of Hurricane Electric account."
  _get "https://dns.he.net/?action=logout"
}

#-- _find_zone() -------------------------------------------------------
# Returns the most specific zone found in administration interface.
#
# Example:
#
# _find_zone first.second.third.co.uk
#
# ... will return the first zone that exists in admin out of these:
# - "first.second.third.co.uk"
# - "second.third.co.uk"
# - "third.co.uk"
# - "co.uk" <-- unlikely
# - "uk"    <-'
#
# (another approach would be something like this:
#   https://github.com/hlandau/acme/blob/master/_doc/dns.hook
#   - that's better if there are multiple pages. It's so much simpler.
# )

_find_zone() {

  _domain="$1"

  if [ -z "$HE_OTP_Secret" ]; then
    body="email=${HE_Username}&pass=${HE_Password}"
  fi

  _matches=$(_post "$body" "https://dns.he.net/" \
    | _egrep_o "delete_dom.*name=\"[^\"]+\" value=\"[0-9]+"
  )
  # Zone names and zone IDs are in same order
  _zone_ids=$(echo "$_matches" | cut -d '"' -f 5)
  _zone_names=$(echo "$_matches" | cut -d '"' -f 3)
  _debug2 "These are the zones on this HE account:"
  _debug2 "$_zone_names"
  _debug2 "And these are their respective IDs:"
  _debug2 "$_zone_ids"

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

    # Take care of "." and only match whole lines. Note that grep -F
    # cannot be used because there's no way to make it match whole
    # lines.
    regex="^$(echo "$_attempted_zone" | sed 's/\./\\./g')$"
    line_num=$(echo "$_zone_names" \
      | grep -n "$regex" \
      | cut -d : -f 1
    )

    if [ -n "$line_num" ]; then
      _zone_id=$(echo "$_zone_ids" | sed "${line_num}q;d")
      _debug "Found relevant zone \"$_attempted_zone\" with id \"$_zone_id\" - will be used for domain \"$_domain\"."
      return 0
    fi

    _debug "Zone \"$_attempted_zone\" doesn't exist, let's try a less specific zone."
    _strip_counter=$(_math "$_strip_counter" + 1)
  done
}
# vim: et:ts=2:sw=2:
