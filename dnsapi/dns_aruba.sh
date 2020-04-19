#!/usr/bin/env sh

#Original Author: Gerardo Trotta <gerardo.trotta@euronet.aero>

#Application username
#ARUBA_AK="xxxxx"
#
#Application password
#ARUBA_AS="xxxxxx"
#
#API key
#ARUBA_TK="xxxxxxxx"
#
#Consumer Key
#ARUBA_CK="sdfsdfsdfsdfsdfdsf"

#ARUBA_END_POINT=aruba-it

#'aruba-business-it'
ARUBA_BUSINESS_IT='https://api.arubabusiness.it'

_aruba_get_api() {
  _ogaep="$1"

  case "${_ogaep}" in

    aruba-b-it | arubabit)
      printf "%s" $ARUBA_BUSINESS_IT
      return
      ;;

    *)

      _err "Unknown parameter : $1"
      return 1
      ;;
  esac
}

_initAuth() {
  ARUBA_AK="${ARUBA_AK:-$(_readaccountconf_mutable ARUBA_AK)}"
  ARUBA_AS="${ARUBA_AS:-$(_readaccountconf_mutable ARUBA_AS)}"
  ARUBA_TK="${ARUBA_TK:-$(_readaccountconf_mutable ARUBA_TK)}"

  if [ -z "$ARUBA_AK" ] || [ -z "$ARUBA_AS" ] || [ -z "$ARUBA_TK" ]; then
    ARUBA_AK=""
    ARUBA_AS=""
    ARUBA_TK=""
    _err "You don't specify ARUBA application key and application secret yet."
    _err "Please create you key and try again."
    return 1
  fi

  if [ "$ARUBA_TK" != "$(_readaccountconf ARUBA_TK)" ]; then
    _info "It seems that your aruba key is changed, let's clear consumer key first."
    _clearaccountconf ARUBA_TK
    _clearaccountconf ARUBA_CK
  fi
  _saveaccountconf_mutable ARUBA_AK "$ARUBA_AK"
  _saveaccountconf_mutable ARUBA_AS "$ARUBA_AS"
  _saveaccountconf_mutable ARUBA_TK "$ARUBA_TK"

  ARUBA_END_POINT="${ARUBA_END_POINT:-$(_readaccountconf_mutable ARUBA_END_POINT)}"
  if [ -z "$ARUBA_END_POINT" ]; then
    ARUBA_END_POINT="aruba-it"
  fi
  _info "Using ARUBA endpoint: $ARUBA_END_POINT"
  if [ "$ARUBA_END_POINT" != "aruba-it" ]; then
    _saveaccountconf_mutable ARUBA_END_POINT "$ARUBA_END_POINT"
  fi

  ARUBA_API="$(_aruba_get_api $ARUBA_END_POINT)"
  _debug ARUBA_API "$ARUBA_API"

  ARUBA_CK="${ARUBA_CK:-$(_readaccountconf_mutable ARUBA_CK)}"
  if [ -z "$ARUBA_CK" ]; then
    _info "ARUBA consumer key is empty, Let's get one:"
    if ! _aruba_authentication; then
      _err "Can not get consumer key."
      #return and wait for retry.
      return 1
    fi
  fi

  _info "Checking authentication and get domain details"

  if ! _aruba_rest GET "api/domains/dns/$_domain/details" || _contains "$response" "error" || _contains "$response" "denied"; then
    _err "The consumer key is invalid: $ARUBA_CK"
    _err "Please retry to create a new one."
    _clearaccountconf ARUBA_CK
    return 1
  fi
  domainData=$(echo "$response" | tr -d '\r')
  # get all Ids and peek only values
  temp="$(echo "$domainData" | _egrep_o "Id\": [^,]*" | cut -d : -f 2 | head -1)" # first element is zone Id
  domain_id=$temp
  _info "DomainId is: $domain_id"
  _info "Consumer key is ok."
  return 0
}

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_aruba_add() {
  fulldomain=$1
  txtvalue=$2

  if ! _initAuth; then
    return 1
  fi
  _debug _domain "$_domain"
  _sub_domain="_acme-challenge"  
  _debug "Check if _acme-challenge record exists in " "$_domain"
  if ! _extract_record_id "$_sub_domain.$_domain."; then
    _method="POST"
  else
    _method="PUT"
  fi

  _payload="{ \"IdDomain\": $domain_id, \"Type\": \"TXT\", \"Name\": \"$_sub_domain\", \"Content\": \"\\\"$txtvalue\\\"\" }"

  _info "Adding record"
  if _aruba_rest "$_method" "api/domains/dns/record" "$_payload"; then
    if _contains "$response" "$txtvalue"; then
      _aruba_rest GET "api/domains/dns/$_domain/details"
      _debug "Refresh:$response"
      _info "Added, sleep 10 seconds."
      _sleep 10
      return 0
    fi
  fi
  _err "Add txt record error."
  return 1
}

#fulldomain
dns_aruba_rm() {
  fulldomain=$1
  txtvalue=$2

  if ! _initAuth; then
    return 1
  fi
  _sub_domain="_acme-challenge"
  _debug "Getting TXT record to delete: $_sub_domain.$_domain."
  if ! _extract_record_id "$_sub_domain.$_domain"; then
    return 1
  fi
  _debug "Deleting TXT record: $_sub_domain.$_domain"
  if ! _aruba_rest DELETE "api/domains/dns/record/$_recordId"; then
    return 1
  fi
  return 0
}

####################  Private functions below ##################################

# returns TXT record and put it in_record_id, if esists
_extract_record_id() {
  subdomain="$1"
  _ids="$(echo "$domainData" | _egrep_o '"Id": [^,]+' | cut -d : -f 2)"
  _debug "$_ids"
  #_temp="$(echo $domainData | grep -oP "\"DomainId\":\s\d{1,}," | tr -d ' ')"
  #_domainids="$(echo $_temp | tr -d ' ')"
  _names="$(echo "$domainData" | _egrep_o '"Name": [^,]*' | cut -d : -f 2)"
  _debug "$_names"
  ARRAY_IDS=$(echo "$_ids" | tr ", " "\n")
  ARRAY_NAMES=$_names
  j=0
  for i in $ARRAY_NAMES; do
    if [ "$i" = "$subdomain" ]; then
      _debug printf "%s\t%s\n" "$i"
      #_arrayname=$i
      _arrayId=$j
      _info "Found txt record id: $_arrayId"
    fi
    j=$(_math "$j" + 1)
  done
  
  n=0
  for i in $ARRAY_IDS; do
    if [ "$n" = "$_arrayId" ]; then
      _recordId=$i
      _info "recordid found: $_recordId"
      return 0
    fi
    n=$(_math "$n" + 1)
  done
  return 1
}

_aruba_authentication() {
  export _H1="Content-Type: application/x-www-form-urlencoded"
  export _H2="Authorization-Key: $ARUBA_TK"
  _H3=""
  _H4=""

  _arubadata="grant_type=password&username=$ARUBA_AK&password=$ARUBA_AS"

  response="$(_post "$_arubadata" "$ARUBA_API/auth/token")"
  _debug "$(_post "$_arubadata" "$ARUBA_API/auth/token")"
  _debug3 response "$response"

  access_token="$(echo "$response" | _egrep_o "access_token\":\"[^\"]*\"" | cut -d : -f 2 | tr -d '"')"
  if [ -z "$access_token" ]; then
    _err "Unable to get access_token"
    return 1
  fi
  _secure_debug access_token "$access_token"

  ARUBA_CK="$access_token"
  _saveaccountconf ARUBA_CK "$ARUBA_CK"
  return 0
}

_aruba_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"

  _aruba_url="$ARUBA_API/$ep"
  _debug2 _aruba_url "$_aruba_url"

  export _H1="Content-type: application/json"
  export _H2="Accept: application/json"
  export _H3="Authorization: Bearer $ARUBA_CK"
  export _H4="Authorization-Key: $ARUBA_TK"
  export _H5="Accept: application/json"
  _debug2 _H3 "$_H3"
  _debug2 _H4 "$_H4"
  if [ "$data" ] || [ "$m" = "POST" ] || [ "$m" = "PUT" ] || [ "$m" = "DELETE" ]; then
    _debug data "$data"
    response="$(_post "$data" "$_aruba_url" "" "$m")"
  else
    response="$(_get "$_aruba_url")"
  fi

  if [ "$?" != "0" ] || _contains "$response" "wrong credentials" || _contains "$response" "Unprocessable" || _contains "$response" "denied"; then
    _err "Response error $response"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
