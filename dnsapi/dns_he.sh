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
    _err "No auth details provided. Please set user credentials using the \$HE_Username and \$HE_Password envoronment variables."
    return 1
  fi
  _saveaccountconf HE_Username "$HE_Username"
  _saveaccountconf HE_Password "$HE_Password"

  # fills in the $_zone_id
  _find_zone "$_full_domain" || return 1
  _debug "Zone id \"$_zone_id\" will be used."

  body="email=${HE_Username}&pass=${HE_Password}"
  body="$body&account="
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
  _debug2 response "$response"
}

#-- dns_he_rm() - Remove TXT record ------------------------------------
# Usage: dns_he_rm _acme-challenge.subdomain.domain.com "XyZ123..."

dns_he_rm() {
  _full_domain=$1
  _txt_value=$2
  _info "Cleaning up after DNS-01 Hurricane Electric hook"

  # fills in the $_zone_id
  _find_zone "$_full_domain" || return 1
  _debug "Zone id \"$_zone_id\" will be used."

  # Find the record id to clean
  body="email=${HE_Username}&pass=${HE_Password}"
  body="$body&hosted_dns_zoneid=$_zone_id"
  body="$body&menu=edit_zone"
  body="$body&hosted_dns_editzone="
  _record_id=$(_post "$body" "https://dns.he.net/" \
    | tr -d '\n' \
    | _egrep_o "data=\"&quot;${_txt_value}&quot;([^>]+>){6}[^<]+<[^;]+;deleteRecord\('[0-9]+','${_full_domain}','TXT'\)" \
    | _egrep_o "[0-9]+','${_full_domain}','TXT'\)$" \
    | _egrep_o "^[0-9]+"
  )
  # The series of egreps above could have been done a bit shorter but
  #  I wanted to double-check whether it's the correct record (in case
  #  HE changes their website somehow).

  # Remove the record
  body="email=${HE_Username}&pass=${HE_Password}"
  body="$body&menu=edit_zone"
  body="$body&hosted_dns_zoneid=$_zone_id"
  body="$body&hosted_dns_recordid=$_record_id"
  body="$body&hosted_dns_editzone=1"
  body="$body&hosted_dns_delrecord=1"
  body="$body&hosted_dns_delconfirm=delete"
  body="$body&hosted_dns_editzone=1"
  _post "$body" "https://dns.he.net/" \
    | grep '<div id="dns_status" onClick="hideThis(this);">Successfully removed record.</div>' \
    >/dev/null
  if [ $? -eq 0 ]; then
    _info "Record removed successfuly."
  else
    _err \
      "Could not clean (remove) up the record. Please go to HE" \
      "administration interface and clean it by hand."
  fi
}

########################## PRIVATE FUNCTIONS ###########################

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

  ## _all_zones is an array that looks like this:
  ## ( zone1:id zone2:id ... )

  body="email=${HE_Username}&pass=${HE_Password}"
  # TODO arrays aren't supported in POSIX sh
  _all_zones=($(_post "$body" "https://dns.he.net/" \
    | _egrep_o "delete_dom.*name=\"[^\"]+\" value=\"[0-9]+" \
    | cut -d '"' -f 3,5 --output-delimiter=":"
  ))

  _strip_counter=1
  while true; do
    _attempted_zone=$(echo "$_domain" | cut -d . -f ${_strip_counter}-)

    # All possible zone names have been tried
    if [ -z "$_attempted_zone" ]; then
      _err "No zone for domain \"$_domain\" found."
      break
    fi

    # Walk through all zones on the account
    #echo "$_all_zones" | while IFS=' ' read _zone_name _zone_id
    for i in ${_all_zones[@]}; do
      _zone_name=$(echo "$i" | cut -d ':' -f 1)
      _zone_id=$(echo "$i" | cut -d ':' -f 2)
      if [ "$_zone_name" = "$_attempted_zone" ]; then
        # Zone found - we got $_zone_name and $_zone_id, let's get out...
        _debug "Found relevant zone \"$_zone_name\" with id" \
          "\"$_zone_id\" - will be used for domain \"$_domain\"."
        return 0
      fi
    done

    _debug "Zone \"$_attempted_zone\" doesn't exist, let's try another \
      variation."
    _strip_counter=$(_math $_strip_counter + 1)
  done

  # No zone found.
  return 1
}

# vim: et:ts=2:sw=2:
