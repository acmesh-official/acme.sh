#!/usr/bin/env sh

#Author: RaidneII
#Created 06/28/2017
#Utilize name.com API to finish dns-01 verifications.
########  Public functions #####################

Namecom_API="https://api.name.com/api"

#Usage: dns_namecom_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_namecom_add() {
  fulldomain=$1
  txtvalue=$2

  # First we need name.com credentials.
  if [ -z "$Namecom_Username" ]; then
    Namecom_Username=""
    _err "Username for name.com is missing."
    _err "Please specify that in your environment variable."
    return 1
  fi

  if [ -z "$Namecom_Token" ]; then
    Namecom_Token=""
    _err "API token for name.com is missing."
    _err "Please specify that in your environment variable."
    return 1
  fi

  # Save them in configuration.
  _saveaccountconf Namecom_Username "$Namecom_Username"
  _saveaccountconf Namecom_Token "$Namecom_Token"

  # Login in using API
  if ! _namecom_login; then
    return 1
  fi

  # Find domain in domain list.
  if ! _namecom_get_root "$fulldomain"; then
    _err "Unable to find domain specified."
    _namecom_logout
    return 1
  fi

  # Add TXT record.
  _namecom_addtxt_json="{\"hostname\":\"$_sub_domain\",\"type\":\"TXT\",\"content\":\"$txtvalue\",\"ttl\":\"300\",\"priority\":\"10\"}"
  if _namecom_rest POST "dns/create/$_domain" "$_namecom_addtxt_json"; then
    retcode=$(printf "%s\n" "$response" | _egrep_o "\"code\":100")
    if [ "$retcode" ]; then
      _info "Successfully added TXT record, ready for validation."
      _namecom_logout
      return 0
    else
      _err "Unable to add the DNS record."
      _namecom_logout
      return 1
    fi
  fi
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_namecom_rm() {
  fulldomain=$1
  txtvalue=$2

  if ! _namecom_login; then
    return 1
  fi

  # Find domain in domain list.
  if ! _namecom_get_root "$fulldomain"; then
    _err "Unable to find domain specified."
    _namecom_logout
    return 1
  fi

  # Get the record id.
  if _namecom_rest GET "dns/list/$_domain"; then
    retcode=$(printf "%s\n" "$response" | _egrep_o "\"code\":100")
    if [ "$retcode" ]; then
      _record_id=$(printf "%s\n" "$response" | _egrep_o "\"record_id\":\"[0-9]+\",\"name\":\"$fulldomain\",\"type\":\"TXT\"" | cut -d \" -f 4)
      _debug record_id "$_record_id"
      _info "Successfully retrieved the record id for ACME challenge."
    else
      _err "Unable to retrieve the record id."
      _namecom_logout
      return 1
    fi
  fi

  # Remove the DNS record using record id.
  _namecom_rmtxt_json="{\"record_id\":\"$_record_id\"}"
  if _namecom_rest POST "dns/delete/$_domain" "$_namecom_rmtxt_json"; then
    retcode=$(printf "%s\n" "$response" | _egrep_o "\"code\":100")
    if [ "$retcode" ]; then
      _info "Successfully removed the TXT record."
      _namecom_logout
      return 0
    else
      _err "Unable to remove the DNS record."
      _namecom_logout
      return 1
    fi
  fi
}

####################  Private functions below ##################################
_namecom_rest() {
  method=$1
  param=$2
  data=$3

  export _H1="Content-Type: application/json"
  export _H2="Api-Session-Token: $sessionkey"
  if [ "$method" != "GET" ]; then
    response="$(_post "$data" "$Namecom_API/$param" "" "$method")"
  else
    response="$(_get "$Namecom_API/$param")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $param"
    return 1
  fi

  _debug2 response "$response"
  return 0
}

_namecom_login() {
  namecom_login_json="{\"username\":\"$Namecom_Username\",\"api_token\":\"$Namecom_Token\"}"

  if _namecom_rest POST "login" "$namecom_login_json"; then
    retcode=$(printf "%s\n" "$response" | _egrep_o "\"code\":100")
    if [ "$retcode" ]; then
      _info "Successfully logged in. Fetching session token..."
      sessionkey=$(printf "%s\n" "$response" | _egrep_o "\"session_token\":\".+" | cut -d \" -f 4)
      if [ ! -z "$sessionkey" ]; then
        _debug sessionkey "$sessionkey"
        _info "Session key obtained."
      else
        _err "Unable to get session key."
        return 1
      fi
    else
      _err "Logging in failed."
      return 1
    fi
  fi
}

_namecom_logout() {
  if _namecom_rest GET "logout"; then
    retcode=$(printf "%s\n" "$response" | _egrep_o "\"code\":100")
    if [ "$retcode" ]; then
      _info "Successfully logged out."
    else
      _err "Error logging out."
      return 1
    fi
  fi
}

_namecom_get_root() {
  domain=$1
  i=2
  p=1

  if ! _namecom_rest GET "domain/list"; then
    return 1
  fi

  # Need to exclude the last field (tld)
  numfields=$(echo "$domain" | _egrep_o "\." | wc -l)
  while [ $i -le $numfields ]; do
    host=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug host "$host"
    if [ -z "$host" ]; then
      return 1
    fi

    if _contains "$response" "$host"; then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
      _domain="$host"
      return 0
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}
