#!/usr/bin/env sh

#
#RAGE4_TOKEN="sdfsdfsdfljlbjkljlkjsdfoiwje"
#
#RAGE4_USERNAME="xxxx@sss.com"

RAGE4_Api="https://rage4.com/rapi/"

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_rage4_add() {
  fulldomain=$1
  txtvalue=$2

  unquotedtxtvalue=$(echo "$txtvalue" | tr -d \")

  RAGE4_USERNAME="${RAGE4_USERNAME:-$(_readaccountconf_mutable RAGE4_USERNAME)}"
  RAGE4_TOKEN="${RAGE4_TOKEN:-$(_readaccountconf_mutable RAGE4_TOKEN)}"

  if [ -z "$RAGE4_USERNAME" ] || [ -z "$RAGE4_TOKEN" ]; then
    RAGE4_USERNAME=""
    RAGE4_TOKEN=""
    _err "You didn't specify a Rage4 api token and username yet."
    return 1
  fi

  #save the api key and email to the account conf file.
  _saveaccountconf_mutable RAGE4_USERNAME "$RAGE4_USERNAME"
  _saveaccountconf_mutable RAGE4_TOKEN "$RAGE4_TOKEN"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"

  _rage4_rest "createrecord/?id=$_domain_id&name=$fulldomain&content=$unquotedtxtvalue&type=TXT&active=true&ttl=1"
  return 0
}

#fulldomain txtvalue
dns_rage4_rm() {
  fulldomain=$1
  txtvalue=$2

  RAGE4_USERNAME="${RAGE4_USERNAME:-$(_readaccountconf_mutable RAGE4_USERNAME)}"
  RAGE4_TOKEN="${RAGE4_TOKEN:-$(_readaccountconf_mutable RAGE4_TOKEN)}"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"

  _debug "Getting txt records"
  _rage4_rest "getrecords/?id=${_domain_id}"

  _record_id=$(echo "$response" | sed -rn 's/.*"id":([[:digit:]]+)[^\}]*'"$txtvalue"'.*/\1/p')
  _rage4_rest "deleterecord/?id=${_record_id}"
  return 0
}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _domain=domain.com
# _domain_id=sdjkglgdfewsdfg
_get_root() {
  domain=$1

  if ! _rage4_rest "getdomains"; then
    return 1
  fi
  _debug _get_root_domain "$domain"

  for line in $(echo "$response" | tr '}' '\n'); do
    __domain=$(echo "$line" | sed -rn 's/.*"name":"([^"]*)",.*/\1/p')
    __domain_id=$(echo "$line" | sed -rn 's/.*"id":([^,]*),.*/\1/p')
    if [ "$domain" != "${domain%"$__domain"*}" ]; then
      _domain_id="$__domain_id"
      break
    fi
  done

  if [ -z "$_domain_id" ]; then
    return 1
  fi

  return 0
}

_rage4_rest() {
  ep="$1"
  _debug "$ep"

  username_trimmed=$(echo "$RAGE4_USERNAME" | tr -d '"')
  token_trimmed=$(echo "$RAGE4_TOKEN" | tr -d '"')
  auth=$(printf '%s:%s' "$username_trimmed" "$token_trimmed" | _base64)

  export _H1="Content-Type: application/json"
  export _H2="Authorization: Basic $auth"

  response="$(_get "$RAGE4_Api$ep")"

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
