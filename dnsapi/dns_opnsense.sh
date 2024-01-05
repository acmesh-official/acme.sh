#!/usr/bin/env sh

#OPNsense Bind API
#https://docs.opnsense.org/development/api.html
#
#OPNs_Host="opnsense.example.com"
#OPNs_Port="443"
# optional, defaults to 443 if unset
#OPNs_Key="qocfU9RSbt8vTIBcnW8bPqCrpfAHMDvj5OzadE7Str+rbjyCyk7u6yMrSCHtBXabgDDXx/dY0POUp7ZA"
#OPNs_Token="pZEQ+3ce8dDlfBBdg3N8EpqpF5I1MhFqdxX06le6Gl8YzyQvYCfCzNaFX9O9+IOSyAs7X71fwdRiZ+Lv"
#OPNs_Api_Insecure=0
# optional, defaults to 0 if unset
# Set 1 for insecure and 0 for secure -> difference is whether ssl cert is checked for validity (0) or whether it is just accepted (1)

########  Public functions #####################
#Usage: add _acme-challenge.www.domain.com "123456789ABCDEF0000000000000000000000000000000000000"
#fulldomain
#txtvalue
OPNs_DefaultPort=443
OPNs_DefaultApi_Insecure=0

dns_opnsense_add() {
  fulldomain=$1
  txtvalue=$2

  _opns_check_auth || return 1

  if ! set_record "$fulldomain" "$txtvalue"; then
    return 1
  fi

  return 0
}

#fulldomain
dns_opnsense_rm() {
  fulldomain=$1
  txtvalue=$2

  _opns_check_auth || return 1

  if ! rm_record "$fulldomain" "$txtvalue"; then
    return 1
  fi

  return 0
}

set_record() {
  fulldomain=$1
  new_challenge=$2
  _info "Adding record $fulldomain with challenge: $new_challenge"

  _debug "Detect root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _domain "$_domain"
  _debug _host "$_host"
  _debug _domainid "$_domainid"
  _return_str=""
  _record_string=""
  _build_record_string "$_domainid" "$_host" "$new_challenge"
  _uuid=""
  if _existingchallenge "$_domain" "$_host" "$new_challenge"; then
    # Update
    if _opns_rest "POST" "/record/setRecord/${_uuid}" "$_record_string"; then
      _return_str="$response"
    else
      return 1
    fi

  else
    #create
    if _opns_rest "POST" "/record/addRecord" "$_record_string"; then
      _return_str="$response"
    else
      return 1
    fi
  fi

  if echo "$_return_str" | _egrep_o "\"result\":\"saved\"" >/dev/null; then
    _opns_rest "POST" "/service/reconfigure" "{}"
    _debug "Record created"
  else
    _err "Error creating record $_record_string"
    return 1
  fi

  return 0
}

rm_record() {
  fulldomain=$1
  new_challenge="$2"
  _info "Remove record $fulldomain with challenge: $new_challenge"

  _debug "Detect root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _domain "$_domain"
  _debug _host "$_host"
  _debug _domainid "$_domainid"
  _uuid=""
  if _existingchallenge "$_domain" "$_host" "$new_challenge"; then
    # Delete
    if _opns_rest "POST" "/record/delRecord/${_uuid}" "\{\}"; then
      if echo "$_return_str" | _egrep_o "\"result\":\"deleted\"" >/dev/null; then
        _opns_rest "POST" "/service/reconfigure" "{}"
        _debug "Record deleted"
      else
        _err "Error deleting record $_host from domain $fulldomain"
        return 1
      fi
    else
      _err "Error deleting record $_host from domain $fulldomain"
      return 1
    fi
  else
    _info "Record not found, nothing to remove"
  fi

  return 0
}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _domainid=domid
#_domain=domain.com
_get_root() {
  domain=$1
  i=2
  p=1
  if _opns_rest "GET" "/domain/searchPrimaryDomain"; then
    _domain_response="$response"
  else
    return 1
  fi

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi
    _debug h "$h"
    id=$(echo "$_domain_response" | _egrep_o "\"uuid\":\"[a-z0-9\-]*\",\"enabled\":\"1\",\"type\":\"primary\",\"domainname\":\"${h}\"" | cut -d ':' -f 2 | cut -d '"' -f 2)
    if [ -n "$id" ]; then
      _debug id "$id"
      _host=$(printf "%s" "$domain" | cut -d . -f 1-$p)
      _domain="${h}"
      _domainid="${id}"
      return 0
    fi
    p=$i
    i=$(_math $i + 1)
  done
  _debug "$domain not found"

  return 1
}

_opns_rest() {
  method=$1
  ep=$2
  data=$3
  #Percent encode user and token
  key=$(echo "$OPNs_Key" | tr -d "\n\r" | _url_encode)
  token=$(echo "$OPNs_Token" | tr -d "\n\r" | _url_encode)

  opnsense_url="https://${key}:${token}@${OPNs_Host}:${OPNs_Port:-$OPNs_DefaultPort}/api/bind${ep}"
  export _H1="Content-Type: application/json"
  _debug2 "Try to call api: https://${OPNs_Host}:${OPNs_Port:-$OPNs_DefaultPort}/api/bind${ep}"
  if [ ! "$method" = "GET" ]; then
    _debug data "$data"
    export _H1="Content-Type: application/json"
    response="$(_post "$data" "$opnsense_url" "" "$method")"
  else
    export _H1=""
    response="$(_get "$opnsense_url")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"

  return 0
}

_build_record_string() {
  _record_string="{\"record\":{\"enabled\":\"1\",\"domain\":\"$1\",\"name\":\"$2\",\"type\":\"TXT\",\"value\":\"$3\"}}"
}

_existingchallenge() {
  if _opns_rest "GET" "/record/searchRecord"; then
    _record_response="$response"
  else
    return 1
  fi
  _uuid=""
  _uuid=$(echo "$_record_response" | _egrep_o "\"uuid\":\"[^\"]*\",\"enabled\":\"[01]\",\"domain\":\"$1\",\"name\":\"$2\",\"type\":\"TXT\",\"value\":\"$3\"" | cut -d ':' -f 2 | cut -d '"' -f 2)

  if [ -n "$_uuid" ]; then
    _debug uuid "$_uuid"
    return 0
  fi
  _debug "${2}.$1{1} record not found"

  return 1
}

_opns_check_auth() {
  OPNs_Host="${OPNs_Host:-$(_readaccountconf_mutable OPNs_Host)}"
  OPNs_Port="${OPNs_Port:-$(_readaccountconf_mutable OPNs_Port)}"
  OPNs_Key="${OPNs_Key:-$(_readaccountconf_mutable OPNs_Key)}"
  OPNs_Token="${OPNs_Token:-$(_readaccountconf_mutable OPNs_Token)}"
  OPNs_Api_Insecure="${OPNs_Api_Insecure:-$(_readaccountconf_mutable OPNs_Api_Insecure)}"

  if [ -z "$OPNs_Host" ]; then
    _err "You don't specify OPNsense address."
    return 1
  else
    _saveaccountconf_mutable OPNs_Host "$OPNs_Host"
  fi

  if ! printf '%s' "$OPNs_Port" | grep '^[0-9]*$' >/dev/null; then
    _err 'OPNs_Port specified but not numeric value'
    return 1
  elif [ -z "$OPNs_Port" ]; then
    _info "OPNSense port not specified. Defaulting to using port $OPNs_DefaultPort"
  else
    _saveaccountconf_mutable OPNs_Port "$OPNs_Port"
  fi

  if ! printf '%s' "$OPNs_Api_Insecure" | grep '^[01]$' >/dev/null; then
    _err 'OPNs_Api_Insecure specified but not 0/1 value'
    return 1
  elif [ -n "$OPNs_Api_Insecure" ]; then
    _saveaccountconf_mutable OPNs_Api_Insecure "$OPNs_Api_Insecure"
  fi
  export HTTPS_INSECURE="${OPNs_Api_Insecure:-$OPNs_DefaultApi_Insecure}"

  if [ -z "$OPNs_Key" ]; then
    _err "you have not specified your OPNsense api key id."
    _err "Please set OPNs_Key and try again."
    return 1
  else
    _saveaccountconf_mutable OPNs_Key "$OPNs_Key"
  fi

  if [ -z "$OPNs_Token" ]; then
    _err "you have not specified your OPNsense token."
    _err "Please create OPNs_Token and try again."
    return 1
  else
    _saveaccountconf_mutable OPNs_Token "$OPNs_Token"
  fi

  if ! _opns_rest "GET" "/general/get"; then
    _err "Call to OPNsense API interface failed. Unable to access OPNsense API."
    return 1
  fi
  return 0
}
