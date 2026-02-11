#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_infomaniak_info='Infomaniak.com
Site: Infomaniak.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_infomaniak
Options:
 INFOMANIAK_API_TOKEN API Token
Issues: github.com/acmesh-official/acme.sh/issues/3188

'

# To use this API you need visit the API dashboard of your account.
# Note: the URL looks like this:
# https://manager.infomaniak.com/v3/<account_id>/ng/profile/user/token/list
# Then generate a token with following scopes :
#  - domain:read
#  - dns:read
#  - dns:write
# this is given as an environment variable INFOMANIAK_API_TOKEN

# base variables

DEFAULT_INFOMANIAK_API_URL="https://api.infomaniak.com"
DEFAULT_INFOMANIAK_TTL=300

########  Public functions #####################

#Usage: dns_infomaniak_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_infomaniak_add() {

  INFOMANIAK_API_TOKEN="${INFOMANIAK_API_TOKEN:-$(_readaccountconf_mutable INFOMANIAK_API_TOKEN)}"
  INFOMANIAK_API_URL="${INFOMANIAK_API_URL:-$(_readaccountconf_mutable INFOMANIAK_API_URL)}"
  INFOMANIAK_TTL="${INFOMANIAK_TTL:-$(_readaccountconf_mutable INFOMANIAK_TTL)}"

  if [ -z "$INFOMANIAK_API_TOKEN" ]; then
    INFOMANIAK_API_TOKEN=""
    _err "Please provide a valid Infomaniak API token in variable INFOMANIAK_API_TOKEN"
    return 1
  fi

  if [ -z "$INFOMANIAK_API_URL" ]; then
    INFOMANIAK_API_URL="$DEFAULT_INFOMANIAK_API_URL"
  fi

  if [ -z "$INFOMANIAK_TTL" ]; then
    INFOMANIAK_TTL="$DEFAULT_INFOMANIAK_TTL"
  fi

  #save the token to the account conf file.
  _saveaccountconf_mutable INFOMANIAK_API_TOKEN "$INFOMANIAK_API_TOKEN"

  if [ "$INFOMANIAK_API_URL" != "$DEFAULT_INFOMANIAK_API_URL" ]; then
    _saveaccountconf_mutable INFOMANIAK_API_URL "$INFOMANIAK_API_URL"
  fi

  if [ "$INFOMANIAK_TTL" != "$DEFAULT_INFOMANIAK_TTL" ]; then
    _saveaccountconf_mutable INFOMANIAK_TTL "$INFOMANIAK_TTL"
  fi

  export _H1="Authorization: Bearer $INFOMANIAK_API_TOKEN"
  export _H2="Content-Type: application/json"

  fulldomain="$1"
  txtvalue="$2"

  _info "Infomaniak DNS API"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  # guess which base domain to add record to
  zone=$(_get_zone "$fulldomain")
  if [ -z "$zone" ]; then
    _err "cannot find zone:<${zone}> to modify"
    return 1
  fi

  # extract first part of domain
  key=${fulldomain%."$zone"}

  _debug "key:$key"
  _debug "txtvalue: $txtvalue"

  # payload
  data="{\"type\": \"TXT\", \"source\": \"$key\", \"target\": \"$txtvalue\", \"ttl\": $INFOMANIAK_TTL}"

  # API call
  response=$(_post "$data" "${INFOMANIAK_API_URL}/2/zones/${zone}/records")
  if [ -n "$response" ]; then
    if [ ! "$(echo "$response" | _contains '"result":"success"')" ]; then
      _info "Record added"
      _debug "response: $response"
      return 0
    fi
  fi
  _err "Could not create record."
  _debug "Response: $response"
  return 1
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_infomaniak_rm() {

  INFOMANIAK_API_TOKEN="${INFOMANIAK_API_TOKEN:-$(_readaccountconf_mutable INFOMANIAK_API_TOKEN)}"
  INFOMANIAK_API_URL="${INFOMANIAK_API_URL:-$(_readaccountconf_mutable INFOMANIAK_API_URL)}"
  INFOMANIAK_TTL="${INFOMANIAK_TTL:-$(_readaccountconf_mutable INFOMANIAK_TTL)}"

  if [ -z "$INFOMANIAK_API_TOKEN" ]; then
    INFOMANIAK_API_TOKEN=""
    _err "Please provide a valid Infomaniak API token in variable INFOMANIAK_API_TOKEN."
    return 1
  fi

  if [ -z "$INFOMANIAK_API_URL" ]; then
    INFOMANIAK_API_URL="$DEFAULT_INFOMANIAK_API_URL"
  fi

  if [ -z "$INFOMANIAK_TTL" ]; then
    INFOMANIAK_TTL="$DEFAULT_INFOMANIAK_TTL"
  fi

  #save the token to the account conf file.
  _saveaccountconf_mutable INFOMANIAK_API_TOKEN "$INFOMANIAK_API_TOKEN"

  if [ "$INFOMANIAK_API_URL" != "$DEFAULT_INFOMANIAK_API_URL" ]; then
    _saveaccountconf_mutable INFOMANIAK_API_URL "$INFOMANIAK_API_URL"
  fi

  if [ "$INFOMANIAK_TTL" != "$DEFAULT_INFOMANIAK_TTL" ]; then
    _saveaccountconf_mutable INFOMANIAK_TTL "$INFOMANIAK_TTL"
  fi

  export _H1="Authorization: Bearer $INFOMANIAK_API_TOKEN"
  export _H2="ContentType: application/json"

  fulldomain=$1
  txtvalue=$2
  _info "Infomaniak DNS API"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  # guess which base domain to add record to
  zone=$(_get_zone "$fulldomain")
  if [ -z "$zone" ]; then
    _err "cannot find zone:<$zone> to modify"
    return 1
  fi

  # extract first part of domain
  key=${fulldomain%."$zone"}
  key=$(echo "$key" | _lower_case)

  _debug "zone:$zone"
  _debug "key:$key"

  # find previous record
  # shellcheck disable=SC2086
  response=$(_get "${INFOMANIAK_API_URL}/2/zones/${zone}/records" | sed 's/.*"data":\[\(.*\)\]}/\1/; s/},{/}{/g')
  record_id=$(echo "$response" | sed -n 's/.*"id":"*\([0-9]*\)"*.*"source":"'"$key"'".*"target":"\\"'"$txtvalue"'\\"".*/\1/p')
  _debug "key: $key"
  _debug "txtvalue: $txtvalue"
  _debug "record_id: $record_id"

  if [ -z "$record_id" ]; then
    _err "could not find record to delete"
    _debug "response: $response"
    return 1
  fi

  # API call
  response=$(_post "" "${INFOMANIAK_API_URL}/2/zones/${zone}/records/${record_id}" "" DELETE)
  if [ -n "$response" ]; then
    if [ ! "$(echo "$response" | _contains '"result":"success"')" ]; then
      _info "Record deleted"
      return 0
    fi
  fi
  _err "Could not delete record."
  _debug "Response: $response"
  return 1
}

####################  Private functions below ##################################

_get_zone() {
  domain="$1"
  # Whatever the domain is, you can get the fqdn with the following.
  # shellcheck disable=SC1004
  response=$(_get "${INFOMANIAK_API_URL}/2/domains/${domain}/zones" | sed 's/.*\[{"fqdn"\:"\(.*\)/\1/')
  echo "${response%%\"*}"
}
