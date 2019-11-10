#!/usr/bin/env sh

#Author: meowthink
#Created 01/14/2017
#Utilize namesilo.com API to finish dns-01 verifications.

Namesilo_API="https://www.namesilo.com/api"

########  Public functions #####################

#Usage: dns_myapi_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_namesilo_add() {
  fulldomain=$1
  txtvalue=$2

  if [ -z "$Namesilo_Key" ]; then
    Namesilo_Key=""
    _err "API token for namesilo.com is missing."
    _err "Please specify that in your environment variable."
    return 1
  fi

  #save the api key and email to the account conf file.
  _saveaccountconf Namesilo_Key "$Namesilo_Key"

  if ! _get_root "$fulldomain"; then
    _err "Unable to find domain specified."
    return 1
  fi

  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug txtvalue "$txtvalue"
  if _namesilo_rest GET "dnsAddRecord?version=1&type=xml&key=$Namesilo_Key&domain=$_domain&rrtype=TXT&rrhost=$_sub_domain&rrvalue=$txtvalue"; then
    retcode=$(printf "%s\n" "$response" | _egrep_o "<code>300")
    if [ "$retcode" ]; then
      _info "Successfully added TXT record, ready for validation."
      return 0
    else
      _err "Unable to add the DNS record."
      return 1
    fi
  fi
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_namesilo_rm() {
  fulldomain=$1
  txtvalue=$2

  if ! _get_root "$fulldomain"; then
    _err "Unable to find domain specified."
    return 1
  fi

  # Get the record id.
  if _namesilo_rest GET "dnsListRecords?version=1&type=xml&key=$Namesilo_Key&domain=$_domain"; then
    retcode=$(printf "%s\n" "$response" | _egrep_o "<code>300")
    if [ "$retcode" ]; then
      _record_id=$(echo "$response" | _egrep_o "<record_id>([^<]*)</record_id><type>TXT</type><host>$fulldomain</host>" | _egrep_o "<record_id>([^<]*)</record_id>" | sed -r "s/<record_id>([^<]*)<\/record_id>/\1/" | tail -n 1)
      _debug _record_id "$_record_id"
      if [ "$_record_id" ]; then
        _info "Successfully retrieved the record id for ACME challenge."
      else
        _info "Empty record id, it seems no such record."
        return 0
      fi
    else
      _err "Unable to retrieve the record id."
      return 1
    fi
  fi

  # Remove the DNS record using record id.
  if _namesilo_rest GET "dnsDeleteRecord?version=1&type=xml&key=$Namesilo_Key&domain=$_domain&rrid=$_record_id"; then
    retcode=$(printf "%s\n" "$response" | _egrep_o "<code>300")
    if [ "$retcode" ]; then
      _info "Successfully removed the TXT record."
      return 0
    else
      _err "Unable to remove the DNS record."
      return 1
    fi
  fi
}

####################  Private functions below ##################################

# _acme-challenge.www.domain.com
# returns
#  _sub_domain=_acme-challenge.www
#  _domain=domain.com
_get_root() {
  domain=$1
  i=2
  p=1

  if ! _namesilo_rest GET "listDomains?version=1&type=xml&key=$Namesilo_Key"; then
    return 1
  fi

  # Need to exclude the last field (tld)
  numfields=$(echo "$domain" | _egrep_o "\." | wc -l)
  while [ $i -le "$numfields" ]; do
    host=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug host "$host"
    if [ -z "$host" ]; then
      return 1
    fi

    if _contains "$response" "<domain>$host"; then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
      _domain="$host"
      return 0
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

_namesilo_rest() {
  method=$1
  param=$2
  data=$3

  if [ "$method" != "GET" ]; then
    response="$(_post "$data" "$Namesilo_API/$param" "" "$method")"
  else
    response="$(_get "$Namesilo_API/$param")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $param"
    return 1
  fi

  _debug2 response "$response"
  return 0
}
