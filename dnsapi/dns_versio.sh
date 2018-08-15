#!/usr/bin/env sh
#
#Author: lebaned
#Report Bugs here: https://github.com/lebaned/acme.sh
#
########  Public functions #####################

#Usage: dns_versio_add   _acme-challenge.www.domain.com   "[txtvalue]"
dns_versio_add() {
  fulldomain=$1
  txtvalue=$2
  _info "Using Versio"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"


  if ! _get_credentials; then
    return 1
  fi
  
  #save the credentials to the account conf file.
  _saveaccountconf_mutable Versio_Username  "$Versio_Username"
  _saveaccountconf_mutable Versio_Password  "$Versio_Password"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _info fulldomain "$fulldomain"
  _info _domain "$_domain"
  _info _sub_domain "$_sub_domain"
  
  if ! _get_dns_records "$_domain"; then
    _err "invalid domain"
    return 1
  fi

  _debug "orginal dnsrecords" "$_dns_records"
  _delete_dns_record "TXT" "$fulldomain."
  _debug "dnsrecords after deleted old record" "$_dns_records"
  _add_dns_record "TXT" "$fulldomain" "\\\"$txtvalue\\\"" 0 300
  _debug "dnsrecords after add record" "{\"dns_records\":[$_dns_records]}"

  if _versio_rest POST "domains/$_domain/update" "{\"dns_records\":[$_dns_records]}"; then
    _debug "rest update response" "$response"
    return 0
  fi

  _err "Error!"
  return 1
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_versio_rm() {
  fulldomain=$1
  txtvalue=$2
  _info "Using Versio"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  if ! _get_credentials; then
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _info fulldomain "$fulldomain"
  _info _domain "$_domain"
  _info _sub_domain "$_sub_domain"

  if ! _get_dns_records "$_domain"; then
    _err "invalid domain"
    return 1
  fi

  _debug "orginal dnsrecords" "$_dns_records"
  _delete_dns_record "TXT" "$fulldomain."
  _debug "dnsrecords after deleted old record" "$_dns_records"

  if _versio_rest POST "domains/$_domain/update" "{\"dns_records\":[$_dns_records]}"; then
    _debug "rest update response" "$response"
    return 0
  fi

  _err "Error!"
  return 1

}

####################  Private functions below ##################################



#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
_get_root() {
  domain=$1
  i=2
  p=1

  if _versio_rest GET "domains?status=OK"; then
    response="$(echo "$response" | tr -d "\n" | sed 's/{/\n&/g')"
    while true; do
      h=$(printf "%s" "$domain" | cut -d . -f $i-100)
      _info h "$h"
      _debug h "$h"
      if [ -z "$h" ]; then
        #not valid
        return 1
      fi

      hostedzone="$(echo "$response" | _egrep_o "{.*\"domain\":\s*\"$h\".*}")"
      if [ "$hostedzone" ]; then
        _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
        _domain=$h
        return 0
      fi
      p=$i
      i=$(_math "$i" + 1)
    done
  fi
  return 1
}

#parameters: [record type] [record name]
_delete_dns_record() {
  _dns_records=$(echo $_dns_records | sed 's/{"type":"'"$1"'","name":"'"$2"'"[^}]*}[,]\?//' | sed 's/,$//')
}

#parameters: [type] [name] [value] [prio] [ttl]
_add_dns_record() {
  _dns_records="$_dns_records,{\"type\":\"$1\",\"name\":\"$2\",\"value\":\"$3\",\"prio\":$4,\"ttl\":$5}"
}

#parameters: [root domain]
#returns
# _dns_records
_get_dns_records() {

  if _versio_rest GET "domains/$1?show_dns_records=true"; then
    _dns_records=$(echo $response | grep -oP '(?<="dns_records":\[)[^\]]*')
    return 0
  fi
  return 1
}

#method uri qstr data
_versio_rest() {
  mtd="$1"
  ep="$2"
  data="$3"

  _debug mtd "$mtd"
  _debug ep "$ep"

  VERSIO_API_URL="https://www.versio.nl/api/v1"
  
  export _H1="Accept: application/json"
  export _H2="Content-Type: application/json"
  export _H3="Authorization: Basic $(echo -n """$Versio_Username:$Versio_Password""" | openssl enc -base64)"
  
  if [ "$mtd" != "GET" ]; then
    # both POST and DELETE.
    _debug data "$data"
    response="$(_post "$data" "$VERSIO_API_URL/$ep" "" "$mtd")"
  else
    response="$(_get "$VERSIO_API_URL/$ep")"
  fi
  
  case $? in
  0)
    ;;
  6)
    _err "Authentication failure. Check your Versio email address and password"
    return 1
    ;;
  *)
    _err "Unknown error"
    return 1
    ;;
  esac
  
  _debug response "$response"
  return 0
}

#parameters: []
#returns:
#  Versio_Username
#  Versio_Password
_get_credentials() {
  Versio_Username="${Versio_Username:-$(_readaccountconf_mutable Versio_Username)}"
  Versio_Password="${Versio_Password:-$(_readaccountconf_mutable Versio_Password)}"
  if [ -z "$Versio_Username" ] || [ -z "$Versio_Password" ]; then
    Versio_Username=""
    Versio_Password=""
    _err "You don't specify Versio email address and/or password yet."
    _err "Example:"
    _err "export Versio_Username=[email address]"
    _err "export Versio_Password=[password]"
    _err "Please create you key and try again."
    return 1
  fi
  return 0
}
