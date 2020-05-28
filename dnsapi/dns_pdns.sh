#!/usr/bin/env sh

#PowerDNS Embedded API
#https://doc.powerdns.com/md/httpapi/api_spec/
#
#PDNS_Url="http://ns.example.com:8081"
#PDNS_ServerId="localhost"
#PDNS_Token="0123456789ABCDEF"
#PDNS_Ttl=60

DEFAULT_PDNS_TTL=60

########  Public functions #####################
#Usage: add _acme-challenge.www.domain.com "123456789ABCDEF0000000000000000000000000000000000000"
#fulldomain
#txtvalue
dns_pdns_add() {
  fulldomain=$1
  txtvalue=$2

  if [ -z "$PDNS_Url" ]; then
    PDNS_Url=""
    _err "You don't specify PowerDNS address."
    _err "Please set PDNS_Url and try again."
    return 1
  fi

  if [ -z "$PDNS_ServerId" ]; then
    PDNS_ServerId=""
    _err "You don't specify PowerDNS server id."
    _err "Please set you PDNS_ServerId and try again."
    return 1
  fi

  if [ -z "$PDNS_Token" ]; then
    PDNS_Token=""
    _err "You don't specify PowerDNS token."
    _err "Please create you PDNS_Token and try again."
    return 1
  fi

  if [ -z "$PDNS_Ttl" ]; then
    PDNS_Ttl="$DEFAULT_PDNS_TTL"
  fi

  #save the api addr and key to the account conf file.
  _saveaccountconf PDNS_Url "$PDNS_Url"
  _saveaccountconf PDNS_ServerId "$PDNS_ServerId"
  _saveaccountconf PDNS_Token "$PDNS_Token"

  if [ "$PDNS_Ttl" != "$DEFAULT_PDNS_TTL" ]; then
    _saveaccountconf PDNS_Ttl "$PDNS_Ttl"
  fi

  _debug "Detect root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain "$_domain"

  if ! set_record "$_domain" "$fulldomain" "$txtvalue"; then
    return 1
  fi

  return 0
}

#fulldomain
dns_pdns_rm() {
  fulldomain=$1
  txtvalue=$2

  if [ -z "$PDNS_Ttl" ]; then
    PDNS_Ttl="$DEFAULT_PDNS_TTL"
  fi

  _debug "Detect root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _domain "$_domain"

  if ! rm_record "$_domain" "$fulldomain" "$txtvalue"; then
    return 1
  fi

  return 0
}

set_record() {
  _info "Adding record"
  root=$1
  full=$2
  new_challenge=$3

  _record_string=""
  _build_record_string "$new_challenge"
  _list_existingchallenges
  for oldchallenge in $_existing_challenges; do
    _build_record_string "$oldchallenge"
  done

  if ! _pdns_rest "PATCH" "/api/v1/servers/$PDNS_ServerId/zones/$root" "{\"rrsets\": [{\"changetype\": \"REPLACE\", \"name\": \"$full.\", \"type\": \"TXT\", \"ttl\": $PDNS_Ttl, \"records\": [$_record_string]}]}"; then
    _err "Set txt record error."
    return 1
  fi

  if ! notify_slaves "$root"; then
    return 1
  fi

  return 0
}

rm_record() {
  _info "Remove record"
  root=$1
  full=$2
  txtvalue=$3

  #Enumerate existing acme challenges
  _list_existingchallenges

  if _contains "$_existing_challenges" "$txtvalue"; then
    #Delete all challenges (PowerDNS API does not allow to delete content)
    if ! _pdns_rest "PATCH" "/api/v1/servers/$PDNS_ServerId/zones/$root" "{\"rrsets\": [{\"changetype\": \"DELETE\", \"name\": \"$full.\", \"type\": \"TXT\"}]}"; then
      _err "Delete txt record error."
      return 1
    fi
    _record_string=""
    #If the only existing challenge was the challenge to delete: nothing to do
    if ! [ "$_existing_challenges" = "$txtvalue" ]; then
      for oldchallenge in $_existing_challenges; do
        #Build up the challenges to re-add, ommitting the one what should be deleted
        if ! [ "$oldchallenge" = "$txtvalue" ]; then
          _build_record_string "$oldchallenge"
        fi
      done
      #Recreate the existing challenges
      if ! _pdns_rest "PATCH" "/api/v1/servers/$PDNS_ServerId/zones/$root" "{\"rrsets\": [{\"changetype\": \"REPLACE\", \"name\": \"$full.\", \"type\": \"TXT\", \"ttl\": $PDNS_Ttl, \"records\": [$_record_string]}]}"; then
        _err "Set txt record error."
        return 1
      fi
    fi
    if ! notify_slaves "$root"; then
      return 1
    fi
  else
    _info "Record not found, nothing to remove"
  fi

  return 0
}

notify_slaves() {
  root=$1

  if ! _pdns_rest "PUT" "/api/v1/servers/$PDNS_ServerId/zones/$root/notify"; then
    _err "Notify slaves error."
    return 1
  fi

  return 0
}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _domain=domain.com
_get_root() {
  domain=$1
  i=1

  if _pdns_rest "GET" "/api/v1/servers/$PDNS_ServerId/zones"; then
    _zones_response="$response"
  fi

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)

    if _contains "$_zones_response" "\"name\": \"$h.\""; then
      _domain="$h."
      if [ -z "$h" ]; then
        _domain="=2E"
      fi
      return 0
    fi

    if [ -z "$h" ]; then
      return 1
    fi
    i=$(_math $i + 1)
  done
  _debug "$domain not found"

  return 1
}

_pdns_rest() {
  method=$1
  ep=$2
  data=$3

  export _H1="X-API-Key: $PDNS_Token"

  if [ ! "$method" = "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$PDNS_Url$ep" "" "$method")"
  else
    response="$(_get "$PDNS_Url$ep")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"

  return 0
}

_build_record_string() {
  _record_string="${_record_string:+${_record_string}, }{\"content\": \"\\\"${1}\\\"\", \"disabled\": false}"
}

_list_existingchallenges() {
  _pdns_rest "GET" "/api/v1/servers/$PDNS_ServerId/zones/$root"
  _existing_challenges=$(echo "$response" | _normalizeJson | _egrep_o "\"name\":\"${fulldomain}[^]]*}" | _egrep_o 'content\":\"\\"[^\\]*' | sed -n 's/^content":"\\"//p')
}
