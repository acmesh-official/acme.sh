#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_wts_info='Wärner Technologie Services
Site: Waerner-TechServices.de
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_wts
Options:
 WTS_API_Token API Token
Issues: github.com/acmesh-official/acme.sh/issues/6372
Author: Lukas Wärner (CEO)
'

WTS_API="https://wts-api.de/hosting/domain"
########  Public functions ######################

# TMP_RecordID=0 # Temporary Id of the creazed record will be safed here.

TMP_DIR="/tmp/acme-wts"
mkdir -p "$TMP_DIR"
TMP_RECORD_FILE="$TMP_DIR/${fulldomain//\*/_}.record_id"

#Usage: dns_wts_add _acme-challenge.domain.waerner-techservices.de "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_wts_add() {
  fulldomain=$1
  txtvalue=$2

  WTS_API_Token="${WTS_API_Token:-$(_readaccountconf_mutable WTS_API_Token)}"
  if [ -z "$WTS_API_Token" ]; then
    _err "You must export variable: WTS_API_Token"
    _err "The API Key for your WTS account is necessary."
    _err "You can look it up in your WTS account."
    return 1
  fi

  # Now save the credentials.
  _saveaccountconf_mutable WTS_API_Token "$WTS_API_Token"

  if ! _get_root "$fulldomain"; then
    _err "invalid domain" "$fulldomain"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  # convert to lower case
  _domain="$(echo "$_domain" | _lower_case)"
  _sub_domain="$(echo "$_sub_domain" | _lower_case)"
  
  # Now add the TXT record
  _info "Trying to add TXT record"
  if _WTS_rest "POST" "/$_domain/records/add/txt/$_sub_domain/$txtvalue?WTS-API-Token=$WTS_API_Token"; then
    _info "TXT record has been successfully added."
    # export TMP_RecordID="$(echo "$_response" | _egrep_o '"record_id"[[:space:]]*:[[:space:]]*[0-9]+' | cut -d ':' -f2 | tr -d ' ')"
    TMP_RecordID="$(echo "$_response" | _egrep_o '"record_id"[[:space:]]*:[[:space:]]*[0-9]+' | cut -d ':' -f2 | tr -d ' ')"
    # TMP_RECORD_FILE="/tmp/acme-wts/${fulldomain//\*/_}.record_id"
    # mkdir -p /tmp/acme-wts
    #  echo "$TMP_RecordID" > "$TMP_RECORD_FILE"
    _saveaccountconf_mutable "_WTS_RecordID_$fulldomain" "$TMP_RecordID"
    _info "Saved TMP_RecordID=$TMP_RecordID"


    return 0
  else
    _err "Errors happened during adding the TXT record, response=$_response"
    return 1
  fi


}

#Usage: fulldomain txtvalue
#Usage: dns_wts_rm _acme-challenge.domain.waerner-techservices.de "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
#Remove the txt record after validation.
dns_wts_rm() {
  fulldomain=$1
  txtvalue=$2

  WTS_API_Token="${WTS_API_Token:-$(_readaccountconf_mutable WTS_API_Token)}"
  if [ -z "$WTS_API_Token" ]; then
    _err "You must export variable: WTS_API_Token"
    _err "The API Key for your WTS account is necessary."
    _err "You can look it up in your WTS account."
    return 1
  fi

  if ! _get_root "$fulldomain"; then
    _err "invalid domain" "$fulldomain"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  # convert to lower case
  _domain="$(echo "$_domain" | _lower_case)"
  _sub_domain="$(echo "$_sub_domain" | _lower_case)"
  # Now delete the TXT record
  _info "Trying to delete TXT record"

  # TMP_RECORD_FILE="/tmp/acme-wts/${fulldomain//\*/_}.record_id"

  # if [ -f "$TMP_RECORD_FILE" ]; then
    # TMP_RecordID="$(cat "$TMP_RECORD_FILE")"
    # rm -f "$TMP_RECORD_FILE"
    # _debug "Loaded TMP_RecordID=$TMP_RecordID from $TMP_RECORD_FILE"
  # else
    # _err "TMP_RecordID file not found for domain $fulldomain"
    # return 1
  # fi

  TMP_RecordID="$(_readaccountconf_mutable "_WTS_RecordID_$fulldomain")"

  if [ -z "$TMP_RecordID" ]; then
    _err "TMP_RecordID not found. Cannot delete record."
    return 1
  fi

  _info "Using TMP_RecordID: $TMP_RecordID"

  if _WTS_rest "DELETE" "/$_domain/records/remove/$TMP_RecordID?WTS-API-Token=$WTS_API_Token"; then
    _info "TXT record has been successfully deleted."
    return 0
  else
    if [ -z "$TMP_RecordID" ]; then
     _err "Errors happened during deleting the TXT record, because the temporary record-id from creation is not set."
     return 1
    else:
     _err "Errors happened during deleting the TXT record, response=$_response"
     return 1
    fi
  fi

}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
_get_root() {
  domain="$1"
  i=1
  p=1

  WTS_API_Token="${WTS_API_Token:-$(_readaccountconf_mutable WTS_API_Token)}"

  _WTS_get "list?WTS-API-Token=$WTS_API_Token"
  domain_data=$_response

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    #if _contains "$domain_data" "\""$h"\"\:"; then
    if _contains "$domain_data" "\"""$h""\"\:"; then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-"$p")
      _domain="$h"
      return 0
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

#send get request to api
# $1 has to set the api-function
_WTS_get() {
  url="$WTS_API/$1"
  export _H1="Authorization: Bearer $WTS_API_Token"

  _response=$(_get "$url")
  _response="$(echo "$_response" | _normalizeJson)"

  if _contains "$_response" "429 Too Many Requests"; then
    _info "API throttled, sleeping to reset the limit"
    _sleep 10
    _response=$(_get "$url")
    _response="$(echo "$_response" | _normalizeJson)"
  fi
}

_WTS_rest() {
  url="$WTS_API"
  export _H1="Authorization: Bearer $WTS_API_Token"
  export _H2="Content-Type: application/x-www-form-urlencoded"
  

  method="$1"
  path="$2"
  full_url="$WTS_API$path"

  export _H1="Authorization: Bearer $WTS_API_Token"
  export _H2="Content-Type: application/x-www-form-urlencoded"

  if [ "$method" = "POST" ]; then
    _response=$(_post "" "$full_url")
  elif [ "$method" = "DELETE" ]; then
    _response=$(_post "" "$full_url" "" "DELETE")
  else
    _response=$(_get "$full_url")
  fi

  if _contains "$_response" "429 Too Many Requests"; then
    _info "API throttled, sleeping to reset the limit"
    _sleep 10
    if [ "$method" = "POST" ]; then
      _response=$(_post "" "$full_url")
    elif [ "$method" = "DELETE" ]; then
      _response=$(_post "" "$full_url" "" "DELETE")
    else
      _response=$(_get "$full_url")
    fi
  fi

  _debug2 response "$_response"
  echo "$_response" | grep -q "\"info\":\"success\""


  if _contains "$_response" '"error_desc":"Error while deleting dns-record."'; then
    return 1
  fi

  if ! _contains "$_response" '"success":true'; then
    return 1
  fi
  _debug2 response "$_response"
  return 0
}
