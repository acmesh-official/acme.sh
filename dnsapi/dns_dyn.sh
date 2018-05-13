#!/usr/bin/env sh
#
# Dyn.com Domain API
#
# Author: Gerd Naschenweng
# https://github.com/magicdude4eva
#
# Dyn Managed DNS API
# https://help.dyn.com/dns-api-knowledge-base/
#
# It is recommended to add a "Dyn Managed DNS" user specific for API access.
# The "Zones & Records Permissions" required by this script are:
# --
# RecordAdd
# RecordUpdate
# RecordDelete
# RecordGet
# ZoneGet
# ZoneAddNode
# ZoneRemoveNode
# ZonePublish
# --
#
# Pass credentials before "acme.sh --issue --dns dns_dyn ..."
# --
# export DYN_Customer="customer"
# export DYN_Username="apiuser"
# export DYN_Password="secret"
# --

DYN_API="https://api.dynect.net/REST"

#REST_API
########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "Challenge-code"
dns_dyn_add() {
  fulldomain="$1"
  txtvalue="$2"

  DYN_Customer="${DYN_Customer:-$(_readaccountconf_mutable DYN_Customer)}"
  DYN_Username="${DYN_Username:-$(_readaccountconf_mutable DYN_Username)}"
  DYN_Password="${DYN_Password:-$(_readaccountconf_mutable DYN_Password)}"
  if [ -z "$DYN_Customer" ] || [ -z "$DYN_Username" ] || [ -z "$DYN_Password" ]; then
    DYN_Customer=""
    DYN_Username=""
    DYN_Password=""
    _err "You must export variables: DYN_Customer, DYN_Username and DYN_Password"
    return 1
  fi

  #save the config variables to the account conf file.
  _saveaccountconf_mutable DYN_Customer "$DYN_Customer"
  _saveaccountconf_mutable DYN_Username "$DYN_Username"
  _saveaccountconf_mutable DYN_Password "$DYN_Password"

  if ! _dyn_get_authtoken; then
    return 1
  fi

  if [ -z "$_dyn_authtoken" ]; then
    _dyn_end_session
    return 1
  fi

  if ! _dyn_get_zone; then
    _dyn_end_session
    return 1
  fi

  if ! _dyn_add_record; then
    _dyn_end_session
    return 1
  fi

  if ! _dyn_publish_zone; then
    _dyn_end_session
    return 1
  fi

  _dyn_end_session

  return 0
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_dyn_rm() {
  fulldomain="$1"
  txtvalue="$2"

  DYN_Customer="${DYN_Customer:-$(_readaccountconf_mutable DYN_Customer)}"
  DYN_Username="${DYN_Username:-$(_readaccountconf_mutable DYN_Username)}"
  DYN_Password="${DYN_Password:-$(_readaccountconf_mutable DYN_Password)}"
  if [ -z "$DYN_Customer" ] || [ -z "$DYN_Username" ] || [ -z "$DYN_Password" ]; then
    DYN_Customer=""
    DYN_Username=""
    DYN_Password=""
    _err "You must export variables: DYN_Customer, DYN_Username and DYN_Password"
    return 1
  fi

  if ! _dyn_get_authtoken; then
    return 1
  fi

  if [ -z "$_dyn_authtoken" ]; then
    _dyn_end_session
    return 1
  fi

  if ! _dyn_get_zone; then
    _dyn_end_session
    return 1
  fi

  if ! _dyn_get_record_id; then
    _dyn_end_session
    return 1
  fi

  if [ -z "$_dyn_record_id" ]; then
    _dyn_end_session
    return 1
  fi

  if ! _dyn_rm_record; then
    _dyn_end_session
    return 1
  fi

  if ! _dyn_publish_zone; then
    _dyn_end_session
    return 1
  fi

  _dyn_end_session

  return 0
}

####################  Private functions below ##################################

#get Auth-Token
_dyn_get_authtoken() {

  _info "Start Dyn API Session"

  data="{\"customer_name\":\"$DYN_Customer\", \"user_name\":\"$DYN_Username\", \"password\":\"$DYN_Password\"}"
  dyn_url="$DYN_API/Session/"
  method="POST"

  _debug data "$data"
  _debug dyn_url "$dyn_url"

  export _H1="Content-Type: application/json"

  response="$(_post "$data" "$dyn_url" "" "$method")"
  sessionstatus="$(printf "%s\n" "$response" | _egrep_o '"status" *: *"[^"]*' | _head_n 1 | sed 's#^"status" *: *"##')"

  _debug response "$response"
  _debug sessionstatus "$sessionstatus"

  if [ "$sessionstatus" = "success" ]; then
    _dyn_authtoken="$(printf "%s\n" "$response" | _egrep_o '"token" *: *"[^"]*' | _head_n 1 | sed 's#^"token" *: *"##')"
    _info "Token received"
    _debug _dyn_authtoken "$_dyn_authtoken"
    return 0
  fi

  _dyn_authtoken=""
  _err "get token failed"
  return 1
}

#fulldomain=_acme-challenge.www.domain.com
#returns
# _dyn_zone=domain.com
_dyn_get_zone() {
  i=2
  while true; do
    domain="$(printf "%s" "$fulldomain" | cut -d . -f "$i-100")"
    if [ -z "$domain" ]; then
      break
    fi

    dyn_url="$DYN_API/Zone/$domain/"

    export _H1="Auth-Token: $_dyn_authtoken"
    export _H2="Content-Type: application/json"

    response="$(_get "$dyn_url" "" "")"
    sessionstatus="$(printf "%s\n" "$response" | _egrep_o '"status" *: *"[^"]*' | _head_n 1 | sed 's#^"status" *: *"##')"

    _debug dyn_url "$dyn_url"
    _debug response "$response"
    _debug sessionstatus "$sessionstatus"

    if [ "$sessionstatus" = "success" ]; then
      _dyn_zone="$domain"
      return 0
    fi
    i=$(_math "$i" + 1)
  done

  _dyn_zone=""
  _err "get zone failed"
  return 1
}

#add TXT record
_dyn_add_record() {

  _info "Adding TXT record"

  data="{\"rdata\":{\"txtdata\":\"$txtvalue\"},\"ttl\":\"300\"}"
  dyn_url="$DYN_API/TXTRecord/$_dyn_zone/$fulldomain/"
  method="POST"

  export _H1="Auth-Token: $_dyn_authtoken"
  export _H2="Content-Type: application/json"

  response="$(_post "$data" "$dyn_url" "" "$method")"
  sessionstatus="$(printf "%s\n" "$response" | _egrep_o '"status" *: *"[^"]*' | _head_n 1 | sed 's#^"status" *: *"##')"

  _debug response "$response"
  _debug sessionstatus "$sessionstatus"

  if [ "$sessionstatus" = "success" ]; then
    _info "TXT Record successfully added"
    return 0
  fi

  _err "add TXT record failed"
  return 1
}

#publish the zone
_dyn_publish_zone() {

  _info "Publishing zone"

  data="{\"publish\":\"true\"}"
  dyn_url="$DYN_API/Zone/$_dyn_zone/"
  method="PUT"

  export _H1="Auth-Token: $_dyn_authtoken"
  export _H2="Content-Type: application/json"

  response="$(_post "$data" "$dyn_url" "" "$method")"
  sessionstatus="$(printf "%s\n" "$response" | _egrep_o '"status" *: *"[^"]*' | _head_n 1 | sed 's#^"status" *: *"##')"

  _debug response "$response"
  _debug sessionstatus "$sessionstatus"

  if [ "$sessionstatus" = "success" ]; then
    _info "Zone published"
    return 0
  fi

  _err "publish zone failed"
  return 1
}

#get record_id of TXT record so we can delete the record
_dyn_get_record_id() {

  _info "Getting record_id of TXT record"

  dyn_url="$DYN_API/TXTRecord/$_dyn_zone/$fulldomain/"

  export _H1="Auth-Token: $_dyn_authtoken"
  export _H2="Content-Type: application/json"

  response="$(_get "$dyn_url" "" "")"
  sessionstatus="$(printf "%s\n" "$response" | _egrep_o '"status" *: *"[^"]*' | _head_n 1 | sed 's#^"status" *: *"##')"

  _debug response "$response"
  _debug sessionstatus "$sessionstatus"

  if [ "$sessionstatus" = "success" ]; then
    _dyn_record_id="$(printf "%s\n" "$response" | _egrep_o "\"data\" *: *\[\"/REST/TXTRecord/$_dyn_zone/$fulldomain/[^\"]*" | _head_n 1 | sed "s#^\"data\" *: *\[\"/REST/TXTRecord/$_dyn_zone/$fulldomain/##")"
    _debug _dyn_record_id "$_dyn_record_id"
    return 0
  fi

  _dyn_record_id=""
  _err "getting record_id failed"
  return 1
}

#delete TXT record
_dyn_rm_record() {

  _info "Deleting TXT record"

  dyn_url="$DYN_API/TXTRecord/$_dyn_zone/$fulldomain/$_dyn_record_id/"
  method="DELETE"

  _debug dyn_url "$dyn_url"

  export _H1="Auth-Token: $_dyn_authtoken"
  export _H2="Content-Type: application/json"

  response="$(_post "" "$dyn_url" "" "$method")"
  sessionstatus="$(printf "%s\n" "$response" | _egrep_o '"status" *: *"[^"]*' | _head_n 1 | sed 's#^"status" *: *"##')"

  _debug response "$response"
  _debug sessionstatus "$sessionstatus"

  if [ "$sessionstatus" = "success" ]; then
    _info "TXT record successfully deleted"
    return 0
  fi

  _err "delete TXT record failed"
  return 1
}

#logout
_dyn_end_session() {

  _info "End Dyn API Session"

  dyn_url="$DYN_API/Session/"
  method="DELETE"

  _debug dyn_url "$dyn_url"

  export _H1="Auth-Token: $_dyn_authtoken"
  export _H2="Content-Type: application/json"

  response="$(_post "" "$dyn_url" "" "$method")"

  _debug response "$response"

  _dyn_authtoken=""
  return 0
}
