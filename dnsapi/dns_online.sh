#!/usr/bin/env sh

# Online API
# https://console.online.net/en/api/
#
# Requires Online API key set in ONLINE_API_KEY

########  Public functions #####################

ONLINE_API="https://api.online.net/api/v1"

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_online_add() {
  fulldomain=$1
  txtvalue=$2

  if ! _online_check_config; then
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"
  _debug _real_dns_version "$_real_dns_version"

  _info "Creating temporary zone version"
  _online_create_temporary_zone_version
  _info "Enabling temporary zone version"
  _online_enable_zone "$_temporary_dns_version"

  _info "Adding record"
  _online_create_TXT_record "$_real_dns_version" "$_sub_domain" "$txtvalue"
  _info "Disabling temporary version"
  _online_enable_zone "$_real_dns_version"
  _info "Destroying temporary version"
  _online_destroy_zone "$_temporary_dns_version"

  _info "Record added."
  return 0
}

#fulldomain
dns_online_rm() {
  fulldomain=$1
  txtvalue=$2

  if ! _online_check_config; then
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"
  _debug _real_dns_version "$_real_dns_version"

  _debug "Getting txt records"
  if ! _online_rest GET "domain/$_domain/version/active"; then
    return 1
  fi

  rid=$(echo "$response" | _egrep_o "\"id\":[0-9]+,\"name\":\"$_sub_domain\",\"data\":\"\\\u0022$txtvalue\\\u0022\"" | cut -d ':' -f 2 | cut -d ',' -f 1)
  _debug rid "$rid"
  if [ -z "$rid" ]; then
    return 1
  fi

  _info "Creating temporary zone version"
  _online_create_temporary_zone_version
  _info "Enabling temporary zone version"
  _online_enable_zone "$_temporary_dns_version"

  _info "Removing DNS record"
  _online_rest DELETE "domain/$_domain/version/$_real_dns_version/zone/$rid"
  _info "Disabling temporary version"
  _online_enable_zone "$_real_dns_version"
  _info "Destroying temporary version"
  _online_destroy_zone "$_temporary_dns_version"

  return 0
}

####################  Private functions below ##################################

_online_check_config() {
  ONLINE_API_KEY="${ONLINE_API_KEY:-$(_readaccountconf_mutable ONLINE_API_KEY)}"
  if [ -z "$ONLINE_API_KEY" ]; then
    _err "No API key specified for Online API."
    _err "Create your key and export it as ONLINE_API_KEY"
    return 1
  fi
  if ! _online_rest GET "domain/"; then
    _err "Invalid API key specified for Online API."
    return 1
  fi

  _saveaccountconf_mutable ONLINE_API_KEY "$ONLINE_API_KEY"

  return 0
}

#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
_get_root() {
  domain=$1
  i=2
  p=1
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    _online_rest GET "domain/$h/version/active"

    if ! _contains "$response" "Domain not found" >/dev/null; then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
      _domain="$h"
      _real_dns_version=$(echo "$response" | _egrep_o '"uuid_ref":.*' | cut -d ':' -f 2 | cut -d '"' -f 2)
      return 0
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  _err "Unable to retrive DNS zone matching this domain"
  return 1
}

# this function create a temporary zone version
# as online.net does not allow updating an active version
_online_create_temporary_zone_version() {

  _online_rest POST "domain/$_domain/version" "name=acme.sh"
  if [ "$?" != "0" ]; then
    return 1
  fi

  _temporary_dns_version=$(echo "$response" | _egrep_o '"uuid_ref":.*' | cut -d ':' -f 2 | cut -d '"' -f 2)

  # Creating a dummy record in this temporary version, because online.net doesn't accept enabling an empty version
  _online_create_TXT_record "$_temporary_dns_version" "dummy.acme.sh" "dummy"

  return 0
}

_online_destroy_zone() {
  version_id=$1
  _online_rest DELETE "domain/$_domain/version/$version_id"

  if [ "$?" != "0" ]; then
    return 1
  fi
  return 0
}

_online_enable_zone() {
  version_id=$1
  _online_rest PATCH "domain/$_domain/version/$version_id/enable"

  if [ "$?" != "0" ]; then
    return 1
  fi
  return 0
}

_online_create_TXT_record() {
  version=$1
  txt_name=$2
  txt_value=$3

  _online_rest POST "domain/$_domain/version/$version/zone" "type=TXT&name=$txt_name&data=%22$txt_value%22&ttl=60&priority=0"

  # Note : the normal, expected response SHOULD be "Unknown method".
  # this happens because the API HTTP response contains a Location: header, that redirect
  # to an unknown online.net endpoint.
  if [ "$?" != "0" ] || _contains "$response" "Unknown method" || _contains "$response" "\$ref"; then
    return 0
  else
    _err "error $response"
    return 1
  fi
}

_online_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"
  _online_url="$ONLINE_API/$ep"
  _debug2 _online_url "$_online_url"
  export _H1="Authorization: Bearer $ONLINE_API_KEY"
  export _H2="X-Pretty-JSON: 1"
  if [ "$data" ] || [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$_online_url" "" "$m")"
  else
    response="$(_get "$_online_url")"
  fi
  if [ "$?" != "0" ] || _contains "$response" "invalid_grant" || _contains "$response" "Method not allowed"; then
    _err "error $response"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
