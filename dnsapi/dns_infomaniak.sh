#!/usr/bin/env sh

###############################################################################
# Infomaniak API integration
#
# To use this API you need visit the API dashboard of your account
# once logged into https://manager.infomaniak.com add /api/dashboard to the URL
#
# Please report bugs to
# https://github.com/acmesh-official/acme.sh/issues/3188
#
# Note: the URL looks like this:
# https://manager.infomaniak.com/v3/<account_id>/api/dashboard
# Then generate a token with the scope Domain
# this is given as an environment variable INFOMANIAK_API_TOKEN
###############################################################################

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

  fqdn=${fulldomain#_acme-challenge.}

  # guess which base domain to add record to
  zone_and_id=$(_find_zone "$fqdn")
  if [ -z "$zone_and_id" ]; then
    _err "cannot find zone to modify"
    return 1
  fi
  zone=${zone_and_id% *}
  domain_id=${zone_and_id#* }

  # extract first part of domain
  key=${fulldomain%.$zone}

  _debug "zone:$zone id:$domain_id key:$key"

  # payload
  data="{\"type\": \"TXT\", \"source\": \"$key\", \"target\": \"$txtvalue\", \"ttl\": $INFOMANIAK_TTL}"

  # API call
  response=$(_post "$data" "${INFOMANIAK_API_URL}/1/domain/$domain_id/dns/record")
  if [ -n "$response" ] && echo "$response" | _contains '"result":"success"'; then
    _info "Record added"
    _debug "Response: $response"
    return 0
  fi
  _err "could not create record"
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
  export _H2="ContentType: application/json"

  fulldomain=$1
  txtvalue=$2
  _info "Infomaniak DNS API"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  fqdn=${fulldomain#_acme-challenge.}

  # guess which base domain to add record to
  zone_and_id=$(_find_zone "$fqdn")
  if [ -z "$zone_and_id" ]; then
    _err "cannot find zone to modify"
    return 1
  fi
  zone=${zone_and_id% *}
  domain_id=${zone_and_id#* }

  # extract first part of domain
  key=${fulldomain%.$zone}

  _debug "zone:$zone id:$domain_id key:$key"

  # find previous record
  # shellcheck disable=SC1004
  record_id=$(_get "${INFOMANIAK_API_URL}/1/domain/$domain_id/dns/record" | sed 's/.*"data":\[\(.*\)\]}/\1/; s/},{/}\
{/g' | sed -n 's/.*"id":"*\([0-9]*\)"*.*"source_idn":"'"$fulldomain"'".*"target_idn":"'"$txtvalue"'".*/\1/p')
  if [ -z "$record_id" ]; then
    _err "could not find record to delete"
    return 1
  fi
  _debug "record_id: $record_id"

  # API call
  response=$(_post "" "${INFOMANIAK_API_URL}/1/domain/$domain_id/dns/record/$record_id" "" DELETE)
  if [ -n "$response" ] && echo "$response" | _contains '"result":"success"'; then
    _info "Record deleted"
    return 0
  fi
  _err "could not delete record"
  return 1
}

####################  Private functions below ##################################

_get_domain_id() {
  domain="$1"

  # shellcheck disable=SC1004
  _get "${INFOMANIAK_API_URL}/1/product?service_name=domain&customer_name=$domain" | sed 's/.*"data":\[{\(.*\)}\]}/\1/; s/,/\
/g' | sed -n 's/^"id":\(.*\)/\1/p'
}

_find_zone() {
  zone="$1"

  # find domain in list, removing . parts sequentialy
  while _contains "$zone" '\.'; do
    _debug "testing $zone"
    id=$(_get_domain_id "$zone")
    if [ -n "$id" ]; then
      echo "$zone $id"
      return
    fi
    zone=${zone#*.}
  done
}
