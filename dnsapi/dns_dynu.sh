#!/usr/bin/env sh

my_dir="$(dirname "$0")"
source "$my_dir/acme.sh"

#Client ID
Dynu_ClientId="0b71cae7-a099-4f6b-8ddf-94571cdb760d"
#
#Secret
Dynu_Secret="aCUEY4BDCV45KI8CSIC3sp2LKQ9"
#
#Token
Dynu_Token=""
#
#Endpoint
Dynu_EndPoint="https://api.dynu.com/v1"

########  Public functions #####################

#Usage: add _acme-challenge.www.domain.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_dynu_add() {
  fulldomain=$1
  txtvalue=$2

  if [ -z "$Dynu_ClientId" ] || [ -z "$Dynu_Secret" ]; then
    Dynu_ClientId=""
    Dynu_Secret=""
    _err "Dynu client id and secret is not specified."
    _err "Please create you API client id and secret and try again."
    return 1
  fi

  #save the client id and secret to the account conf file.
  _saveaccountconf Dynu_ClientId "$Dynu_ClientId"
  _saveaccountconf Dynu_Secret "$Dynu_Secret"

  if [ -z "$Dynu_Token" ]; then
    _info "Getting Dynu token"
    if ! _dynu_authentication; then
      _err "Can not get token."
    fi
  fi

  _debug "Detect root zone"
  if ! _get_root "$fulldomain"; then
    _err "Invalid domain"
    return 1
  fi    

  _debug _node "$_node"
  _debug _domain_name "$_domain_name"

  _info "Creating TXT record"
  if ! _dynu_rest POST "dns/record/add" "{\"domain_name\":\"$_domain_name\",\"node_name\":\"$_node\",\"record_type\":\"TXT\",\"text_data\":\"$txtvalue\",\"state\":true,\"ttl\":90}"; then
    return 1
  fi

  if ! _contains "$response" "text_data"; then
    _err "Could not add TXT record"
    return 1
  fi

  return 0
}

#fulldomain
dns_dynu_rm() {
  fulldomain=$1
}

########  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _node=_acme-challenge.www
# _domain_name=domain.com
_get_root() {
  domain=$1
  if ! _dynu_rest GET "dns/getroot/$domain"; then
    return 1
  fi

  if ! _contains "$response" "domain_name"; then
    _debug "Domain name not found"
    return 1
  fi

  _domain_name=$(printf "%s" "$response" | tr -d "{}" | cut -d , -f 1 | cut -d : -f 2 | cut -d '"' -f 2)
  _node=$(printf "%s" "$response" | tr -d "{}" | cut -d , -f 3 | cut -d : -f 2 | cut -d '"' -f 2)
  return 0  
}

_dynu_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"

  export _H1="Authorization: Bearer $Dynu_Token"
  export _H2="Content-Type: application/json"

  if [ "$data" ]; then
    _debug data "$data"
    response="$(_post "$data" "$Dynu_EndPoint/$ep" "" "$m")"
  else
    echo "Getting $Dynu_EndPoint/$ep"
    response="$(_get "$Dynu_EndPoint/$ep")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}

_dynu_authentication() {
  export _H1="Authorization: Basic $(printf "%s" "$Dynu_ClientId:$Dynu_Secret" | _base64)"
  export _H2="Content-Type: application/json"

  response="$(_get "$Dynu_EndPoint/oauth2/token")"
  if [ "$?" != "0" ]; then
    _err "Authentication failed."
    return 1
  fi
  if _contains "$response" "accessToken"; then
    Dynu_Token=$(printf "%s" "$response" | tr -d "[]" | cut -d , -f 2 | cut -d : -f 2 | cut -d '"' -f 2)
  fi
  if _contains "$Dynu_Token" "null"; then
    Dynu_Token=""
  fi
  
  _debug2 response "$response"
  return 0
}
