#!/usr/bin/env sh

# Vultr API
#
# Usage:
#   VULTR_API_KEY needs to be exported with your API key
#
# Recommendations:
#   Vultr supports sub-accounts with limited privileges, and
#   restricting which IPs can originate requests with a
#   given api key - use both or either where you possibly can.
#
# Author: Terry Kerr <root@oefd.ca>
# Report Bugs here: https://github.com/oefd/acme.sh

########  Public functions #####################

dns_vultr_add() {
  fulldomain=$1
  txtvalue=$2
  _info "Using vultr api"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  VULTR_API_KEY="${VULTR_API_KEY:-$(_readaccountconf_mutable VULTR_API_KEY)}"
  if test -z "$VULTR_API_KEY"; then
    VULTR_API_KEY=""
    _err "VULTR_API_KEY was not exported"
    return 1
  fi
  _saveaccountconf_mutable VULTR_API_KEY "$VULTR_API_KEY"

  if ! _split_domain "$fulldomain"; then
    return 1
  fi

  # add the TXT record
  export _H1="Content-Type: application/x-www-form-urlencoded"
  export _H2="Api-Key: $VULTR_API_KEY"
  _endpoint="https://api.vultr.com/v1/dns/create_record"
  _body="domain=$account_domain&name=$sub_domain&data=\"$txtvalue\"&type=TXT"
  _response="$(_post "$_body" "$_endpoint")"
  if test "$?" != "0"; then
    _err "failed adding txt record: $_response"
    return 1
  fi
  _debug2 _response "$_response"

  return 0
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_vultr_rm() {
  fulldomain=$1
  txtvalue=$2
  _info "Using vultr api"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  VULTR_API_KEY="${VULTR_API_KEY:-$(_readaccountconf_mutable VULTR_API_KEY)}"
  if test -z "$VULTR_API_KEY"; then
    VULTR_API_KEY=""
    _err "VULTR_API_KEY was not exported"
    return 1
  fi
  _saveaccountconf_mutable VULTR_API_KEY "$VULTR_API_KEY"

  if ! _split_domain "$fulldomain"; then
    return 1
  fi

  # get domain records for domain
  export _H1="Api-Key: $VULTR_API_KEY"
  _endpoint="https://api.vultr.com/v1/dns/records?domain=$account_domain"
  _response="$(_get "$_endpoint")"
  if test "$?" != "0"; then
    _err "failed getting domain records: $_response"
    return 1
  fi
  _debug2 _records "$_response"

  # grab TXT records (their whole JSON object), then filter them by those 
  # with a name starting with _acme-challenge, then finally filter by the
  # data being equal to $txtvalue.
  _record="$(echo "$_response" | _egrep_o "{[^}]*\"type\"\\s*:\\s*\"TXT\"[^}]*}")"
  _record="$(echo "$_record" | grep "\"name\"\\s*:\\s*\"_acme-challenge")"
  _record="$(echo "$_record" | grep "\"data\"\\s*:\\W*$txtvalue")"
  # take the RECORDID field of the relevant record and get the id value from it
  _record_id="$(echo "$_record" | _egrep_o "\"RECORDID\"\\s*:\\s*[^,]+")"
  _record_id="$(_getfield "$_record_id" 2 ':')"

  # remove the txt record
  export _H1="Content-Type: application/x-www-form-urlencoded"
  export _H2="Api-Key: $VULTR_API_KEY"
  _endpoint="https://api.vultr.com/v1/dns/delete_record"
  _body="domain=$account_domain&RECORDID=$_record_id"
  _response="$(_post "$_body" "$_endpoint")"
  if test "$?" != "0"; then
    _err "error deleting txt record: $_response"
    return 1
  fi
  _debug2 _response "$_response"

  return 0
}

####################  Private functions below ##################################

# break the passed full domain into the sub domain part
# which corrosponds to the record 'name' in vultr, and
# the account domain which is the base domain vultr has
# control of the DNS data for
_split_domain() {
  _domain="$1"

  # get domains for this account
  export _H1="Api-Key: $VULTR_API_KEY"
  _endpoint="https://api.vultr.com/v1/dns/list"
  _domain_list="$(_get "$_endpoint")"
  if test "$?" != "0"; then
    _err "error retrieving account domains: $_domain_list"
    return 1
  fi
  _debug2 _domain_list "$_domain_list"

  # match everything up to the first literal `.` and discard it
  _cut_domain="s/^[^\\.]*\\.//"
  # try each domain formed by stripping a subdomain, stripping
  # before the check to cut the initial _acme-challenge. part
  while _contains "$_domain" "\\."; do
    _domain="$(echo "$_domain" | sed "$_cut_domain")"

    if _contains "$_domain_list" "\"$_domain\""; then
      account_domain="$_domain"
      sub_domain="$(echo "$fulldomain" | sed "s/\\.$_domain\$//")"
      _debug account_domain "$account_domain"
      _debug sub_domain "$sub_domain"
      return 0
    fi
  done

  _err "No domain in vultr account for $1"
  return 1
}
