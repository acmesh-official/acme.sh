#!/usr/bin/env sh

#Script to use with curanet.dk, scannet.dk, wannafind.dk, dandomain.dk DNS management.
#Requires api credentials with scope: dns
#Author: Peter L. Hansen <peter@r12.dk>

CURANET_REST_URL="https://api.curanet.dk/dns/v1/Domains"
CURANET_AUTH_URL="https://apiauth.dk.team.blue/auth/realms/Curanet/protocol/openid-connect/token"
CURANET_ACCESS_TOKEN=""

########  Public functions #####################

#Usage: dns_curanet_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_curanet_add() {
  fulldomain=$1
  txtvalue=$2
  _info "Using curanet"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  CURANET_AUTHCLIENTID="${CURANET_AUTHCLIENTID:-$(_readaccountconf_mutable CURANET_AUTHCLIENTID)}"
  CURANET_AUTHSECRET="${CURANET_AUTHSECRET:-$(_readaccountconf_mutable CURANET_AUTHSECRET)}"
  if [ -z "$CURANET_AUTHCLIENTID" ] || [ -z "$CURANET_AUTHSECRET" ]; then
    CURANET_AUTHCLIENTID=""
    CURANET_AUTHSECRET=""
    _err "You don't specify curanet api client and secret."
    _err "Please create your auth info and try again."
    return 1
  fi

  #save the credentials to the account conf file.
  _saveaccountconf_mutable CURANET_AUTHCLIENTID "$CURANET_AUTHCLIENTID"
  _saveaccountconf_mutable CURANET_AUTHSECRET "$CURANET_AUTHSECRET"

  gettoken

  _get_root "$fulldomain"
  
  export _H1="Content-Type: application/json-patch+json"
  export _H2="Accept: application/json"
  export _H3="Authorization: Bearer $CURANET_ACCESS_TOKEN"
  data="{\"name\": \"$fulldomain\",\"type\": \"TXT\",\"ttl\": 60,\"priority\": 0,\"data\": \"$txtvalue\"}"
  response="$(_post "$data" "$CURANET_REST_URL/${_domain}/Records" "" "")"

  if _contains "$response" "$txtvalue"; then
      _debug "TXT record added OK"
  else
    _err "Unable to add TXT record"
    return 1
  fi

  return 0
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_curanet_rm() {
  fulldomain=$1
  txtvalue=$2
  _info "Using curanet"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"
  
  CURANET_AUTHCLIENTID="${CURANET_AUTHCLIENTID:-$(_readaccountconf_mutable CURANET_AUTHCLIENTID)}"
  CURANET_AUTHSECRET="${CURANET_AUTHSECRET:-$(_readaccountconf_mutable CURANET_AUTHSECRET)}"

  gettoken

  _get_root "$fulldomain"
  
  _debug "Getting current record list to identify TXT to delete"

  export _H1="Content-Type: application/json"
  export _H2="Accept: application/json"
  export _H3="Authorization: Bearer $CURANET_ACCESS_TOKEN"

  response="$(_get "$CURANET_REST_URL/${_domain}/Records" "" "")"

  if ! _contains "$response" "$txtvalue"; then
    _err "Unable to delete record (does not contain $txtvalue )"
    return 1
  fi

  recordid=$(echo "$response" | _egrep_o "{\"id\":[0-9]+,\"name\":\"$fulldomain\"" | _egrep_o "id\":[0-9]+" | cut -c 5-)

  _debug "Deleting recordID $recordid"
  
  response="$(_post "" "$CURANET_REST_URL/${_domain}/Records/$recordid" "" "DELETE")"

  return 0;
  
}

####################  Private functions below ##################################

gettoken() {
  
  response="$(_post "grant_type=client_credentials&client_id=$CURANET_AUTHCLIENTID&client_secret=$CURANET_AUTHSECRET&scope=dns" "$CURANET_AUTH_URL" "" "")"

  if ! _contains "$response" "access_token"; then
    _err "Unable get access token"
    return 1
  fi

  CURANET_ACCESS_TOKEN=$(echo "$response" | _egrep_o "\"access_token\":\"[^\"]+" | cut -c 17-)

}


#_acme-challenge.www.domain.com
#returns
# _domain=domain.com
# _domain_id=sdjkglgdfewsdfg
_get_root() {
  domain=$1
  i=1

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    export _H1="Content-Type: application/json"
    export _H2="Accept: application/json"
    export _H3="Authorization: Bearer $CURANET_ACCESS_TOKEN"
    response="$(_get "$CURANET_REST_URL/$h/Records" "" "")"

    if [ ! "$(echo "$response" | _egrep_o "Entity not found")" ]; then
      _domain=$h
      return 0
    fi
    
    i=$(_math "$i" + 1)
  done
  return 1
}

