#!/usr/bin/env sh

#
#AZION_Email=""
#AZION_Password=""
#

AZION_Api="https://api.azionapi.net"

########  Public functions ########

# Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
# Used to add txt record
dns_azion_add() {
  fulldomain=$1
  txtvalue=$2

  _debug "Detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "Domain not found"
    return 1
  fi

  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"
  _debug _domain_id "$_domain_id"

  _info "Add or update record"
  _get_record "$_domain_id" "$_sub_domain"
  if [ "$record_id" ]; then
    _payload="{\"record_type\": \"TXT\", \"entry\": \"$_sub_domain\", \"answers_list\": [$answers_list, \"$txtvalue\"], \"ttl\": 20}"
    if _azion_rest PUT "intelligent_dns/$_domain_id/records/$record_id" "$_payload"; then
      if _contains "$response" "$txtvalue"; then
        _info "Record updated."
        return 0
      fi
    fi
  else
    _payload="{\"record_type\": \"TXT\", \"entry\": \"$_sub_domain\", \"answers_list\": [\"$txtvalue\"], \"ttl\": 20}"
    if _azion_rest POST "intelligent_dns/$_domain_id/records" "$_payload"; then
      if _contains "$response" "$txtvalue"; then
        _info "Record added."
        return 0
      fi
    fi
  fi
  _err "Failed to add or update record."
  return 1
}

# Usage: fulldomain txtvalue
# Used to remove the txt record after validation
dns_azion_rm() {
  fulldomain=$1
  txtvalue=$2

  _debug "Detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "Domain not found"
    return 1
  fi

  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"
  _debug _domain_id "$_domain_id"

  _info "Removing record"
  _get_record "$_domain_id" "$_sub_domain"
  if [ "$record_id" ]; then
    if _azion_rest DELETE "intelligent_dns/$_domain_id/records/$record_id"; then
      _info "Record removed."
      return 0
    else
      _err "Failed to remove record."
      return 1
    fi
  else
    _info "Record not found or already removed."
    return 0
  fi
}

####################  Private functions below ##################################
# Usage: _acme-challenge.www.domain.com
# returns
#  _sub_domain=_acme-challenge.www
#  _domain=domain.com
#  _domain_id=sdjkglgdfewsdfg
_get_root() {
  domain=$1
  i=1
  p=1

  if ! _azion_rest GET "intelligent_dns"; then
    return 1
  fi

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      # not valid
      return 1
    fi

    if _contains "$response" "\"domain\":\"$h\""; then
      _domain_id=$(echo "$response" | tr '{' "\n" | grep "\"domain\":\"$h\"" | _egrep_o "\"id\":[0-9]*" | _head_n 1 | cut -d : -f 2 | tr -d \")
      _debug _domain_id "$_domain_id"
      if [ "$_domain_id" ]; then
        _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
        _domain=$h
        return 0
      fi
      return 1
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

_get_record() {
  _domain_id=$1
  _record=$2

  if ! _azion_rest GET "intelligent_dns/$_domain_id/records"; then
    return 1
  fi

  if _contains "$response" "\"entry\":\"$_record\""; then
    _json_record=$(echo "$response" | tr '{' "\n" | grep "\"entry\":\"$_record\"")
    if [ "$_json_record" ]; then
      record_id=$(echo "$_json_record" | _egrep_o "\"record_id\":[0-9]*" | _head_n 1 | cut -d : -f 2 | tr -d \")
      answers_list=$(echo "$_json_record" | _egrep_o "\"answers_list\":\[.*\]" | _head_n 1 | cut -d : -f 2 | tr -d \[\])
      return 0
    fi
    return 1
  fi
  return 1
}

_get_token() {
  AZION_Email="${AZION_Email:-$(_readaccountconf_mutable AZION_Email)}"
  AZION_Password="${AZION_Password:-$(_readaccountconf_mutable AZION_Password)}"

  if ! _contains "$AZION_Email" "@"; then
    _err "It seems that the AZION_Email is not a valid email address. Revalidate your environments."
    return 1
  fi

  if [ -z "$AZION_Email" ] || [ -z "$AZION_Password" ]; then
    _err "You didn't specified a AZION_Email/AZION_Password to generate Azion token."
    return 1
  fi

  _saveaccountconf_mutable AZION_Email "$AZION_Email"
  _saveaccountconf_mutable AZION_Password "$AZION_Password"

  _basic_auth=$(printf "%s:%s" "$AZION_Email" "$AZION_Password" | _base64)
  _debug _basic_auth "$_basic_auth"

  export _H1="Accept: application/json; version=3"
  export _H2="Content-Type: application/json"
  export _H3="Authorization: Basic $_basic_auth"

  response="$(_post "" "$AZION_Api/tokens" "" "POST")"
  if _contains "$response" "\"token\":\"" >/dev/null; then
    _azion_token=$(echo "$response" | _egrep_o "\"token\":\"[^\"]*\"" | cut -d : -f 2 | tr -d \")
    export AZION_Token="$_azion_token"
  else
    _err "Failed to generate Azion token"
    return 1
  fi
}

_azion_rest() {
  _method=$1
  _uri="$2"
  _data="$3"

  if [ -z "$AZION_Token" ]; then
    _get_token
  fi
  _debug2 token "$AZION_Token"

  export _H1="Accept: application/json; version=3"
  export _H2="Content-Type: application/json"
  export _H3="Authorization: token $AZION_Token"

  if [ "$_method" != "GET" ]; then
    _debug _data "$_data"
    response="$(_post "$_data" "$AZION_Api/$_uri" "" "$_method")"
  else
    response="$(_get "$AZION_Api/$_uri")"
  fi

  _debug2 response "$response"

  if [ "$?" != "0" ]; then
    _err "error $_method $_uri $_data"
    return 1
  fi
  return 0
}
