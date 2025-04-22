#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_yandex360_info='Yandex 360 for Business DNS API.
 Yandex 360 for Business is a digital environment for effective collaboration.
Site: https://360.yandex.com/
Docs: https://github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_yandex360
Options:
 YANDEX360_CLIENT_ID OAuth 2.0 ClientID
 YANDEX360_CLIENT_SECRET OAuth 2.0 Client secret
OptionsAlt:
 YANDEX360_ORG_ID Organization ID. Optional.
 YANDEX360_ACCESS_TOKEN OAuth 2.0 Access token. Optional.
Issues: https://github.com/acmesh-official/acme.sh/issues/5213
Author: <Als@admin.ru.net>
'

YANDEX360_API_BASE='https://api360.yandex.net/directory/v1'
YANDEX360_OAUTH_BASE='https://oauth.yandex.ru'

########  Public functions #####################

dns_yandex360_add() {
  fulldomain="$(_idn "$1")"
  txtvalue=$2
  _info 'Using Yandex 360 DNS API'

  if ! _check_variables; then
    return 1
  fi

  if ! _get_root "$fulldomain"; then
    return 1
  fi

  sub_domain=$(echo "$fulldomain" | sed "s/\.$root_domain$//")

  _debug 'Adding Yandex 360 DNS record for subdomain' "$sub_domain"
  dns_api_url="${YANDEX360_API_BASE}/org/${YANDEX360_ORG_ID}/domains/${root_domain}/dns"
  data='{"name":"'"$sub_domain"'","type":"TXT","ttl":60,"text":"'"$txtvalue"'"}'

  response="$(_post "$data" "$dns_api_url" '' 'POST' 'application/json')"

  if _contains "$response" 'recordId'; then
    return 0
  else
    _debug 'Response' "$response"
    return 1
  fi
}

dns_yandex360_rm() {
  fulldomain="$(_idn "$1")"
  txtvalue=$2
  _info 'Using Yandex 360 DNS API'

  if ! _check_variables; then
    return 1
  fi

  if ! _get_root "$fulldomain"; then
    return 1
  fi

  _debug 'Retrieving 100 records from Yandex 360 DNS'
  dns_api_url="${YANDEX360_API_BASE}/org/${YANDEX360_ORG_ID}/domains/${root_domain}/dns?perPage=100"
  response="$(_get "$dns_api_url" '' '')"

  if ! _contains "$response" "$txtvalue"; then
    _info 'DNS record not found. Nothing to remove.'
    _debug 'Response' "$response"
    return 1
  fi

  response="$(echo "$response" | _normalizeJson)"

  record_id=$(
    echo "$response" |
      _egrep_o '\{[^}]*'"${txtvalue}"'[^}]*\}' |
      _egrep_o '"recordId":[0-9]*' |
      cut -d':' -f2
  )

  if [ -z "$record_id" ]; then
    _err 'Unable to get record ID to remove'
    return 1
  fi

  _debug 'Removing DNS record' "$record_id"
  delete_url="${YANDEX360_API_BASE}/org/${YANDEX360_ORG_ID}/domains/${root_domain}/dns/${record_id}"

  response="$(_post '' "$delete_url" '' 'DELETE')"

  if _contains "$response" '{}'; then
    return 0
  else
    _debug 'Response' "$response"
    return 1
  fi
}

####################  Private functions below ##################################

_check_variables() {
  YANDEX360_CLIENT_ID="${YANDEX360_CLIENT_ID:-$(_readaccountconf_mutable YANDEX360_CLIENT_ID)}"
  YANDEX360_CLIENT_SECRET="${YANDEX360_CLIENT_SECRET:-$(_readaccountconf_mutable YANDEX360_CLIENT_SECRET)}"
  YANDEX360_ORG_ID="${YANDEX360_ORG_ID:-$(_readaccountconf_mutable YANDEX360_ORG_ID)}"
  YANDEX360_ACCESS_TOKEN="${YANDEX360_ACCESS_TOKEN:-$(_readaccountconf_mutable YANDEX360_ACCESS_TOKEN)}"
  YANDEX360_REFRESH_TOKEN="${YANDEX360_REFRESH_TOKEN:-$(_readaccountconf_mutable YANDEX360_REFRESH_TOKEN)}"

  if [ -n "$YANDEX360_ACCESS_TOKEN" ]; then
    _info '========================================='
    _info '              ATTENTION'
    _info '========================================='
    _info 'A manually provided Yandex 360 access token has been detected, which is not recommended.'
    _info 'Please note that this token is valid for a limited time after issuance.'
    _info 'It is recommended to obtain the token interactively using acme.sh for one-time setup.'
    _info 'Subsequent token renewals will be handled automatically.'
    _info 'For more details, please visit: https://github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_yandex360'
    _info '========================================='

    _saveaccountconf_mutable YANDEX360_ACCESS_TOKEN "$YANDEX360_ACCESS_TOKEN"
    export _H1="Authorization: OAuth $YANDEX360_ACCESS_TOKEN"

  elif [ -z "$YANDEX360_CLIENT_ID" ] || [ -z "$YANDEX360_CLIENT_SECRET" ]; then
    _err '========================================='
    _err '                 ERROR'
    _err '========================================='
    _err 'The required environment variables YANDEX360_CLIENT_ID and YANDEX360_CLIENT_SECRET are not set.'
    _err 'Alternatively, you can set YANDEX360_ACCESS_TOKEN environment variable.'
    _err 'For more details, please visit: https://github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_yandex360'
    _err '========================================='
    return 1

  else
    _saveaccountconf_mutable YANDEX360_CLIENT_ID "$YANDEX360_CLIENT_ID"
    _saveaccountconf_mutable YANDEX360_CLIENT_SECRET "$YANDEX360_CLIENT_SECRET"

    if [ -n "$YANDEX360_REFRESH_TOKEN" ]; then
      _debug 'Refresh token found. Attempting to refresh access token.'
    fi

    _refresh_token || _get_token || return 1
  fi

  if [ -z "$YANDEX360_ORG_ID" ]; then
    org_response="$(_get "${YANDEX360_API_BASE}/org" '' '')"

    if _contains "$org_response" '"organizations"'; then
      org_response="$(echo "$org_response" | _normalizeJson)"
      YANDEX360_ORG_ID=$(
        echo "$org_response" |
          _egrep_o '"id":[[:space:]]*[0-9]+' |
          cut -d':' -f2
      )
      _debug 'Automatically retrieved YANDEX360_ORG_ID' "$YANDEX360_ORG_ID"
    else
      _err '========================================='
      _err '                 ERROR'
      _err '========================================='
      _err "Failed to retrieve YANDEX360_ORG_ID automatically."
      _err 'For more details, please visit: https://github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_yandex360'
      _err '========================================='
      _debug 'Response' "$org_response"
      return 1
    fi
  fi

  return 0
}

_get_token() {
  _info "$(__red '=========================================')"
  _info "$(__red '                 NOTICE')"
  _info "$(__red '=========================================')"
  _info "$(__red 'Before using the Yandex 360 API, you need to complete an authorization procedure.')"
  _info "$(__red 'The initial access token is obtained interactively and is a one-time operation.')"
  _info "$(__red 'Subsequent API requests will be handled automatically.')"
  _info "$(__red '=========================================')"

  _info 'Initiating device authorization flow'
  device_code_url="${YANDEX360_OAUTH_BASE}/device/code"

  hostname=$(uname -n)
  data="client_id=$YANDEX360_CLIENT_ID&device_id=acme.sh ${hostname}&device_name=acme.sh ${hostname}"

  response="$(_post "$data" "$device_code_url" '' 'POST')"

  if ! _contains "$response" 'device_code'; then
    _err 'Failed to get device code'
    _debug 'Response' "$response"
    return 1
  fi

  response="$(echo "$response" | _normalizeJson)"

  device_code=$(
    echo "$response" |
      _egrep_o '"device_code":"[^"]*"' |
      cut -d'"' -f4
  )
  _debug 'Device code' "$device_code"

  user_code=$(
    echo "$response" |
      _egrep_o '"user_code":"[^"]*"' |
      cut -d'"' -f4
  )
  _debug 'User code' "$user_code"

  verification_url=$(
    echo "$response" |
      _egrep_o '"verification_url":"[^"]*"' |
      cut -d'"' -f4
  )
  _debug 'Verification URL' "$verification_url"

  interval=$(
    echo "$response" |
      _egrep_o '"interval":[[:space:]]*[0-9]+' |
      cut -d':' -f2
  )
  _debug 'Polling interval' "$interval"

  _info "$(__red 'Please visit '"$verification_url"' and log in as an organization administrator')"
  _info "$(__red 'Once logged in, enter the code: '"$user_code"' on the page from the previous step')"
  _info "$(__red 'Waiting for authorization...')"

  _debug 'Polling for token'
  token_url="${YANDEX360_OAUTH_BASE}/token"

  while true; do
    data="grant_type=device_code&code=$device_code&client_id=$YANDEX360_CLIENT_ID&client_secret=$YANDEX360_CLIENT_SECRET"

    response="$(_post "$data" "$token_url" '' 'POST')"

    if _contains "$response" 'access_token'; then
      response="$(echo "$response" | _normalizeJson)"
      YANDEX360_ACCESS_TOKEN=$(
        echo "$response" |
          _egrep_o '"access_token":"[^"]*"' |
          cut -d'"' -f4
      )
      YANDEX360_REFRESH_TOKEN=$(
        echo "$response" |
          _egrep_o '"refresh_token":"[^"]*"' |
          cut -d'"' -f4
      )

      _secure_debug 'Obtained access token' "$YANDEX360_ACCESS_TOKEN"
      _secure_debug 'Obtained refresh token' "$YANDEX360_REFRESH_TOKEN"

      _saveaccountconf_mutable YANDEX360_REFRESH_TOKEN "$YANDEX360_REFRESH_TOKEN"

      export _H1="Authorization: OAuth $YANDEX360_ACCESS_TOKEN"

      _info 'Access token obtained successfully'
      return 0
    elif _contains "$response" 'authorization_pending'; then
      _debug 'Response' "$response"
      _debug "Authorization pending. Waiting $interval seconds before next attempt."
      _sleep "$interval"
    else
      _debug 'Response' "$response"
      _err 'Failed to get access token'
      return 1
    fi
  done
}

_refresh_token() {
  token_url="${YANDEX360_OAUTH_BASE}/token"

  data="grant_type=refresh_token&refresh_token=$YANDEX360_REFRESH_TOKEN&client_id=$YANDEX360_CLIENT_ID&client_secret=$YANDEX360_CLIENT_SECRET"

  response="$(_post "$data" "$token_url" '' 'POST')"

  if _contains "$response" 'access_token'; then
    response="$(echo "$response" | _normalizeJson)"
    YANDEX360_ACCESS_TOKEN=$(
      echo "$response" |
        _egrep_o '"access_token":"[^"]*"' |
        cut -d'"' -f4
    )
    YANDEX360_REFRESH_TOKEN=$(
      echo "$response" |
        _egrep_o '"refresh_token":"[^"]*"' |
        cut -d'"' -f4
    )

    _secure_debug 'Received access token' "$YANDEX360_ACCESS_TOKEN"
    _secure_debug 'Received refresh token' "$YANDEX360_REFRESH_TOKEN"

    _saveaccountconf_mutable YANDEX360_REFRESH_TOKEN "$YANDEX360_REFRESH_TOKEN"

    export _H1="Authorization: OAuth $YANDEX360_ACCESS_TOKEN"

    _info 'Access token refreshed successfully'
    return 0
  else
    _info 'Failed to refresh token. Will attempt to obtain a new one.'
    _debug 'Response' "$response"
    return 1
  fi
}

_get_root() {
  domain="$1"

  for org_id in $YANDEX360_ORG_ID; do
    _debug 'Checking organization ID' "$org_id"
    domains_api_url="${YANDEX360_API_BASE}/org/${org_id}/domains"

    domains_response="$(_get "$domains_api_url" '' '')"

    if ! _contains "$domains_response" '"domains"'; then
      _debug 'No domains found for organization' "$org_id"
      _debug 'Response' "$domains_response"
      continue
    fi

    domains_response="$(echo "$domains_response" | _normalizeJson)"
    domain_names=$(
      echo "$domains_response" |
        _egrep_o '"name":"[^"]*"' |
        cut -d'"' -f4
    )

    for d in $domain_names; do
      d="$(_idn "$d")"
      _debug 'Checking domain' "$d"

      if _endswith "$domain" "$d"; then
        root_domain="$d"
        break
      fi
    done

    if [ -n "$root_domain" ]; then
      _debug "Root domain found: $root_domain in organization $org_id"

      YANDEX360_ORG_ID="$org_id"
      _saveaccountconf_mutable YANDEX360_ORG_ID "$YANDEX360_ORG_ID"

      return 0
    fi
  done

  if [ -z "$root_domain" ]; then
    _err "Could not find a matching root domain for $domain in any organization"
    return 1
  fi
}
