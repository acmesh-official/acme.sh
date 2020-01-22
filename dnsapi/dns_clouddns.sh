#!/usr/bin/env sh

# Author: Radek Sprta <sprta@vshosting.cz>

#CLOUDDNS_EMAIL=XXXXX
#CLOUDDNS_PASSWORD="YYYYYYYYY"
#CLOUDDNS_CLIENT_ID=XXXXX

CLOUDDNS_API='https://admin.vshosting.cloud/clouddns'
CLOUDDNS_LOGIN_API='https://admin.vshosting.cloud/api/public/auth/login'

########  Public functions #####################

# Usage: add _acme-challenge.www.domain.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_clouddns_add() {
  fulldomain=$1
  txtvalue=$2
  _debug "fulldomain" "$fulldomain"

  CLOUDDNS_CLIENT_ID="${CLOUDDNS_CLIENT_ID:-$(_readaccountconf_mutable CLOUDDNS_CLIENT_ID)}"
  CLOUDDNS_EMAIL="${CLOUDDNS_EMAIL:-$(_readaccountconf_mutable CLOUDDNS_EMAIL)}"
  CLOUDDNS_PASSWORD="${CLOUDDNS_PASSWORD:-$(_readaccountconf_mutable CLOUDDNS_PASSWORD)}"

  if [ -z "$CLOUDDNS_PASSWORD" ] || [ -z "$CLOUDDNS_EMAIL" ] || [ -z "$CLOUDDNS_CLIENT_ID" ]; then
    CLOUDDNS_CLIENT_ID=""
    CLOUDDNS_EMAIL=""
    CLOUDDNS_PASSWORD=""
    _err "You didn't specify a CloudDNS password, email and client ID yet."
    return 1
  fi
  if ! _contains "$CLOUDDNS_EMAIL" "@"; then
    _err "It seems that the CLOUDDNS_EMAIL=$CLOUDDNS_EMAIL is not a valid email address."
    _err "Please check and retry."
    return 1
  fi
  # Save CloudDNS client id, email and password to config file
  _saveaccountconf_mutable CLOUDDNS_CLIENT_ID "$CLOUDDNS_CLIENT_ID"
  _saveaccountconf_mutable CLOUDDNS_EMAIL "$CLOUDDNS_EMAIL"
  _saveaccountconf_mutable CLOUDDNS_PASSWORD "$CLOUDDNS_PASSWORD"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "Invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  # Add TXT record
  data="{\"type\":\"TXT\",\"name\":\"$fulldomain.\",\"value\":\"$txtvalue\",\"domainId\":\"$_domain_id\"}"
  if _clouddns_api POST "record-txt" "$data"; then
    if _contains "$response" "$txtvalue"; then
      _info "Added, OK"
    elif _contains "$response" '"code":4136'; then
      _info "Already exists, OK"
    else
      _err "Add TXT record error."
      return 1
    fi
  fi

  _debug "Publishing record changes"
  _clouddns_api PUT "domain/$_domain_id/publish" "{\"soaTtl\":300}"
}

# Usage: rm _acme-challenge.www.domain.com
dns_clouddns_rm() {
  fulldomain=$1
  _debug "fulldomain" "$fulldomain"

  CLOUDDNS_CLIENT_ID="${CLOUDDNS_CLIENT_ID:-$(_readaccountconf_mutable CLOUDDNS_CLIENT_ID)}"
  CLOUDDNS_EMAIL="${CLOUDDNS_EMAIL:-$(_readaccountconf_mutable CLOUDDNS_EMAIL)}"
  CLOUDDNS_PASSWORD="${CLOUDDNS_PASSWORD:-$(_readaccountconf_mutable CLOUDDNS_PASSWORD)}"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "Invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  # Get record ID
  _clouddns_api GET "domain/$_domain_id"
  if _contains "$response" "lastDomainRecordList"; then
    re="\"lastDomainRecordList\".*\"id\":\"([^\"}]*)\"[^}]*\"name\":\"$fulldomain.\","
    _last_domains=$(echo "$response" | _egrep_o "$re")
    re2="\"id\":\"([^\"}]*)\"[^}]*\"name\":\"$fulldomain.\","
    _record_id=$(echo "$_last_domains" | _egrep_o "$re2" | _head_n 1 | cut -d : -f 2 | cut -d , -f 1 | tr -d "\"")
    _debug _record_id "$_record_id"
  else
    _err "Could not retrieve record ID"
    return 1
  fi

  _info "Removing record"
  if _clouddns_api DELETE "record/$_record_id"; then
    if _contains "$response" "\"error\":"; then
      _err "Could not remove record"
      return 1
    fi
  fi

  _debug "Publishing record changes"
  _clouddns_api PUT "domain/$_domain_id/publish" "{\"soaTtl\":300}"
}

####################  Private functions below ##################################

# Usage: _get_root _acme-challenge.www.domain.com
# Returns:
# _sub_domain=_acme-challenge.www
# _domain=domain.com
# _domain_id=sdjkglgdfewsdfg
_get_root() {
  domain=$1

  # Get domain root
  data="{\"search\": [{\"name\": \"clientId\", \"operator\": \"eq\", \"value\": \"$CLOUDDNS_CLIENT_ID\"}]}"
  _clouddns_api "POST" "domain/search" "$data"
  domain_slice="$domain"
  while [ -z "$domain_root" ]; do
    if _contains "$response" "\"domainName\":\"$domain_slice\.\""; then
      domain_root="$domain_slice"
      _debug domain_root "$domain_root"
    fi
    domain_slice="$(echo "$domain_slice" | cut -d . -f 2-)"
  done

  # Get domain id
  data="{\"search\": [{\"name\": \"clientId\", \"operator\": \"eq\", \"value\": \"$CLOUDDNS_CLIENT_ID\"}, \
      {\"name\": \"domainName\", \"operator\": \"eq\", \"value\": \"$domain_root.\"}]}"
  _clouddns_api "POST" "domain/search" "$data"
  if _contains "$response" "\"id\":\""; then
    re='domainType\":\"[^\"]*\",\"id\":\"([^\"]*)\",' # Match domain id
    _domain_id=$(echo "$response" | _egrep_o "$re" | _head_n 1 | cut -d : -f 3 | tr -d "\",")
    if [ "$_domain_id" ]; then
      _sub_domain=$(printf "%s" "$domain" | sed "s/.$domain_root//")
      _domain="$domain_root"
      return 0
    fi
    _err 'Domain name not found on your CloudDNS account'
    return 1
  fi
  return 1
}

# Usage: _clouddns_api GET domain/search '{"data": "value"}'
# Returns:
#  response='{"message": "api response"}'
_clouddns_api() {
  method=$1
  endpoint="$2"
  data="$3"
  _debug endpoint "$endpoint"

  if [ -z "$CLOUDDNS_TOKEN" ]; then
    _clouddns_login
  fi
  _debug CLOUDDNS_TOKEN "$CLOUDDNS_TOKEN"

  export _H1="Content-Type: application/json"
  export _H2="Authorization: Bearer $CLOUDDNS_TOKEN"

  if [ "$method" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$CLOUDDNS_API/$endpoint" "" "$method" | tr -d '\t\r\n ')"
  else
    response="$(_get "$CLOUDDNS_API/$endpoint" | tr -d '\t\r\n ')"
  fi

  # shellcheck disable=SC2181
  if [ "$?" != "0" ]; then
    _err "Error $endpoint"
    return 1
  fi
  _debug2 response "$response"
  return 0
}

# Returns:
#  CLOUDDNS_TOKEN=dslfje2rj23l
_clouddns_login() {
  login_data="{\"email\": \"$CLOUDDNS_EMAIL\", \"password\": \"$CLOUDDNS_PASSWORD\"}"
  response="$(_post "$login_data" "$CLOUDDNS_LOGIN_API" "" "POST" "Content-Type: application/json")"

  if _contains "$response" "\"accessToken\":\""; then
    CLOUDDNS_TOKEN=$(echo "$response" | _egrep_o "\"accessToken\":\"[^\"]*\"" | cut -d : -f 2 | tr -d \")
    export CLOUDDNS_TOKEN
  else
    echo 'Could not get CloudDNS access token; check your credentials'
    return 1
  fi
  return 0
}
