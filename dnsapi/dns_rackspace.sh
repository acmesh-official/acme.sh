#!/usr/bin/env sh
#
#
#RACKSPACE_Username=""
#
#RACKSPACE_Apikey=""

RACKSPACE_Endpoint="https://dns.api.rackspacecloud.com/v1.0"

# 20190213 - The name & id fields swapped in the API response; fix sed
# 20190101 - Duplicating file for new pull request to dev branch
# Original - tcocca:rackspace_dnsapi https://github.com/Neilpang/acme.sh/pull/1297

########  Public functions #####################
#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_rackspace_add() {
  fulldomain="$1"
  _debug fulldomain="$fulldomain"
  txtvalue="$2"
  _debug txtvalue="$txtvalue"
  _rackspace_check_auth || return 1
  _rackspace_check_rootzone || return 1
  _info "Creating TXT record."
  if ! _rackspace_rest POST "$RACKSPACE_Tenant/domains/$_domain_id/records" "{\"records\":[{\"name\":\"$fulldomain\",\"type\":\"TXT\",\"data\":\"$txtvalue\",\"ttl\":300}]}"; then
    return 1
  fi
  _debug2 response "$response"
  if ! _contains "$response" "$txtvalue" >/dev/null; then
    _err "Could not add TXT record."
    return 1
  fi
  return 0
}

#fulldomain txtvalue
dns_rackspace_rm() {
  fulldomain=$1
  _debug fulldomain="$fulldomain"
  txtvalue=$2
  _debug txtvalue="$txtvalue"
  _rackspace_check_auth || return 1
  _rackspace_check_rootzone || return 1
  _info "Checking for TXT record."
  if ! _get_recordid "$_domain_id" "$fulldomain" "$txtvalue"; then
    _err "Could not get TXT record id."
    return 1
  fi
  if [ "$_dns_record_id" = "" ]; then
    _err "TXT record not found."
    return 1
  fi
  _info "Removing TXT record."
  if ! _delete_txt_record "$_domain_id" "$_dns_record_id"; then
    _err "Could not remove TXT record $_dns_record_id."
  fi
  return 0
}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
# _domain_id=sdjkglgdfewsdfg
_get_root_zone() {
  domain="$1"
  i=2
  p=1
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi
    if ! _rackspace_rest GET "$RACKSPACE_Tenant/domains"; then
      return 1
    fi
    _debug2 response "$response"
    if _contains "$response" "\"name\":\"$h\"" >/dev/null; then
      # Response looks like:
      #   {"ttl":300,"accountId":12345,"id":1111111,"name":"example.com","emailAddress": ...<and so on>
      _domain_id=$(echo "$response" | sed -n "s/^.*\"id\":\([^,]*\),\"name\":\"$h\",.*/\1/p")
      _debug2 domain_id "$_domain_id"
      if [ -n "$_domain_id" ]; then
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

_get_recordid() {
  domainid="$1"
  fulldomain="$2"
  txtvalue="$3"
  if ! _rackspace_rest GET "$RACKSPACE_Tenant/domains/$domainid/records?name=$fulldomain&type=TXT"; then
    return 1
  fi
  _debug response "$response"
  if ! _contains "$response" "$txtvalue"; then
    _dns_record_id=0
    return 0
  fi
  _dns_record_id=$(echo "$response" | tr '{' "\n" | grep "\"data\":\"$txtvalue\"" | sed -n 's/^.*"id":"\([^"]*\)".*/\1/p')
  _debug _dns_record_id "$_dns_record_id"
  return 0
}

_delete_txt_record() {
  domainid="$1"
  _dns_record_id="$2"
  if ! _rackspace_rest DELETE "$RACKSPACE_Tenant/domains/$domainid/records?id=$_dns_record_id"; then
    return 1
  fi
  _debug response "$response"
  if ! _contains "$response" "RUNNING"; then
    return 1
  fi
  return 0
}

_rackspace_rest() {
  m="$1"
  ep="$2"
  data="$3"
  _debug ep "$ep"
  export _H1="Accept: application/json"
  export _H2="X-Auth-Token: $RACKSPACE_Token"
  export _H3="X-Project-Id: $RACKSPACE_Tenant"
  export _H4="Content-Type: application/json"
  if [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$RACKSPACE_Endpoint/$ep" "" "$m")"
    retcode=$?
  else
    _info "Getting $RACKSPACE_Endpoint/$ep"
    response="$(_get "$RACKSPACE_Endpoint/$ep")"
    retcode=$?
  fi

  if [ "$retcode" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}

_rackspace_authorization() {
  export _H1="Content-Type: application/json"
  data="{\"auth\":{\"RAX-KSKEY:apiKeyCredentials\":{\"username\":\"$RACKSPACE_Username\",\"apiKey\":\"$RACKSPACE_Apikey\"}}}"
  _debug data "$data"
  response="$(_post "$data" "https://identity.api.rackspacecloud.com/v2.0/tokens" "" "POST")"
  retcode=$?
  _debug2 response "$response"
  if [ "$retcode" != "0" ]; then
    _err "Authentication failed."
    return 1
  fi
  if _contains "$response" "token"; then
    RACKSPACE_Token="$(echo "$response" | _normalizeJson | sed -n 's/^.*"token":{.*,"id":"\([^"]*\)",".*/\1/p')"
    RACKSPACE_Tenant="$(echo "$response" | _normalizeJson | sed -n 's/^.*"token":{.*,"id":"\([^"]*\)"}.*/\1/p')"
    _debug RACKSPACE_Token "$RACKSPACE_Token"
    _debug RACKSPACE_Tenant "$RACKSPACE_Tenant"
  fi
  return 0
}

_rackspace_check_auth() {
  # retrieve the rackspace creds
  RACKSPACE_Username="${RACKSPACE_Username:-$(_readaccountconf_mutable RACKSPACE_Username)}"
  RACKSPACE_Apikey="${RACKSPACE_Apikey:-$(_readaccountconf_mutable RACKSPACE_Apikey)}"
  # check their vals for null
  if [ -z "$RACKSPACE_Username" ] || [ -z "$RACKSPACE_Apikey" ]; then
    RACKSPACE_Username=""
    RACKSPACE_Apikey=""
    _err "You didn't specify a Rackspace username and api key."
    _err "Please set those values and try again."
    return 1
  fi
  # save the username and api key to the account conf file.
  _saveaccountconf_mutable RACKSPACE_Username "$RACKSPACE_Username"
  _saveaccountconf_mutable RACKSPACE_Apikey "$RACKSPACE_Apikey"
  if [ -z "$RACKSPACE_Token" ]; then
    _info "Getting authorization token."
    if ! _rackspace_authorization; then
      _err "Can not get token."
    fi
  fi
}

_rackspace_check_rootzone() {
  _debug "First detect the root zone"
  if ! _get_root_zone "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"
}
