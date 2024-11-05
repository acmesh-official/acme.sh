#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_mythic_beasts_info='Mythic-Beasts.com
Site: Mythic-Beasts.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_mythic_beasts
Options:
 MB_AK API Key
 MB_AS API Secret
Issues: github.com/acmesh-official/acme.sh/issues/3848
'
# Mythic Beasts is a long-standing UK service provider using standards-based OAuth2 authentication
# To test: ./acme.sh --dns dns_mythic_beasts --test --debug 1 --output-insecure --issue --domain domain.com
# Cannot retest once cert is issued
# OAuth2 tokens only valid for 300 seconds so we do not store
# NOTE: This will remove all TXT records matching the fulldomain, not just the added ones (_acme-challenge.www.domain.com)

# Test OAuth2 credentials
#MB_AK="aaaaaaaaaaaaaaaa"
#MB_AS="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

# URLs
MB_API='https://api.mythic-beasts.com/dns/v2/zones'
MB_AUTH='https://auth.mythic-beasts.com/login'

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_mythic_beasts_add() {
  fulldomain=$1
  txtvalue=$2

  _info "MYTHIC BEASTS Adding record $fulldomain = $txtvalue"
  if ! _initAuth; then
    return 1
  fi

  if ! _get_root "$fulldomain"; then
    return 1
  fi

  # method path body_data
  if _mb_rest POST "$_domain/records/$_sub_domain/TXT" "$txtvalue"; then

    if _contains "$response" "1 records added"; then
      _info "Added, verifying..."
      # Max 120 seconds to publish
      for i in $(seq 1 6); do
        # Retry on error
        if ! _mb_rest GET "$_domain/records/$_sub_domain/TXT?verify"; then
          _sleep 20
        else
          _info "Record published!"
          return 0
        fi
      done

    else
      _err "\n$response"
    fi

  fi
  _err "Add txt record error."
  return 1
}

#Usage: rm  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_mythic_beasts_rm() {
  fulldomain=$1
  txtvalue=$2

  _info "MYTHIC BEASTS Removing record $fulldomain = $txtvalue"
  if ! _initAuth; then
    return 1
  fi

  if ! _get_root "$fulldomain"; then
    return 1
  fi

  # method path body_data
  if _mb_rest DELETE "$_domain/records/$_sub_domain/TXT" "$txtvalue"; then
    _info "Record removed"
    return 0
  fi
  _err "Remove txt record error."
  return 1
}

####################  Private functions below ##################################

#Possible formats:
# _acme-challenge.www.example.com
# _acme-challenge.example.com
# _acme-challenge.example.co.uk
# _acme-challenge.www.example.co.uk
# _acme-challenge.sub1.sub2.www.example.co.uk
# sub1.sub2.example.co.uk
# example.com
# example.co.uk
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
_get_root() {
  domain=$1
  i=1
  p=1

  _debug "Detect the root zone"
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    if [ -z "$h" ]; then
      _err "Domain exhausted"
      return 1
    fi

    # Use the status errors to find the domain, continue on 403 Access denied
    # method path body_data
    _mb_rest GET "$h/records"
    ret="$?"
    if [ "$ret" -eq 0 ]; then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-"$p")
      _domain="$h"
      _debug _sub_domain "$_sub_domain"
      _debug _domain "$_domain"
      return 0
    elif [ "$ret" -eq 1 ]; then
      return 1
    fi

    p=$i
    i=$(_math "$i" + 1)

    if [ "$i" -gt 50 ]; then
      break
    fi
  done
  _err "Domain too long"
  return 1
}

_initAuth() {
  MB_AK="${MB_AK:-$(_readaccountconf_mutable MB_AK)}"
  MB_AS="${MB_AS:-$(_readaccountconf_mutable MB_AS)}"

  if [ -z "$MB_AK" ] || [ -z "$MB_AS" ]; then
    MB_AK=""
    MB_AS=""
    _err "Please specify an OAuth2 Key & Secret"
    return 1
  fi

  _saveaccountconf_mutable MB_AK "$MB_AK"
  _saveaccountconf_mutable MB_AS "$MB_AS"

  if ! _oauth2; then
    return 1
  fi

  _info "Checking authentication"
  _secure_debug access_token "$MB_TK"
  _sleep 1

  # GET a list of zones
  # method path body_data
  if ! _mb_rest GET ""; then
    _err "The token is invalid"
    return 1
  fi
  _info "Token OK"
  return 0
}

# Github appears to use an outbound proxy for requests which means subsequent requests may not have the same
# source IP. The standard Mythic Beasts OAuth2 tokens are tied to an IP, meaning github test requests fail
# authentication. This is a work around using an undocumented MB API to obtain a token not tied to an
# IP just for the github tests.
_oauth2() {
  if [ "$GITHUB_ACTIONS" = "true" ]; then
    _oauth2_github
  else
    _oauth2_std
  fi
  return $?
}

_oauth2_std() {
  # HTTP Basic Authentication
  _H1="Authorization: Basic $(echo "$MB_AK:$MB_AS" | _base64)"
  _H2="Accepts: application/json"
  export _H1 _H2
  body="grant_type=client_credentials"

  _info "Getting OAuth2 token..."
  # body  url [needbase64] [POST|PUT|DELETE] [ContentType]
  response="$(_post "$body" "$MB_AUTH" "" "POST" "application/x-www-form-urlencoded")"
  if _contains "$response" "\"token_type\":\"bearer\""; then
    MB_TK="$(echo "$response" | _egrep_o "access_token\":\"[^\"]*\"" | cut -d : -f 2 | tr -d '"')"
    if [ -z "$MB_TK" ]; then
      _err "Unable to get access_token"
      _err "\n$response"
      return 1
    fi
  else
    _err "OAuth2 token_type not Bearer"
    _err "\n$response"
    return 1
  fi
  _debug2 response "$response"
  return 0
}

_oauth2_github() {
  _H1="Accepts: application/json"
  export _H1
  body="{\"login\":{\"handle\":\"$MB_AK\",\"pass\":\"$MB_AS\",\"floating\":1}}"

  _info "Getting Floating token..."
  # body  url [needbase64] [POST|PUT|DELETE] [ContentType]
  response="$(_post "$body" "$MB_AUTH" "" "POST" "application/json")"
  MB_TK="$(echo "$response" | _egrep_o "\"token\":\"[^\"]*\"" | cut -d : -f 2 | tr -d '"')"
  if [ -z "$MB_TK" ]; then
    _err "Unable to get token"
    _err "\n$response"
    return 1
  fi
  _debug2 response "$response"
  return 0
}

# method path body_data
_mb_rest() {
  # URL encoded body for single API operations
  m="$1"
  ep="$2"
  data="$3"

  if [ -z "$ep" ]; then
    _mb_url="$MB_API"
  else
    _mb_url="$MB_API/$ep"
  fi

  _H1="Authorization: Bearer $MB_TK"
  _H2="Accepts: application/json"
  export _H1 _H2
  if [ "$data" ] || [ "$m" = "POST" ] || [ "$m" = "PUT" ] || [ "$m" = "DELETE" ]; then
    # body  url [needbase64] [POST|PUT|DELETE] [ContentType]
    response="$(_post "data=$data" "$_mb_url" "" "$m" "application/x-www-form-urlencoded")"
  else
    response="$(_get "$_mb_url")"
  fi

  if [ "$?" != "0" ]; then
    _err "Request error"
    return 1
  fi

  header="$(cat "$HTTP_HEADER")"
  status="$(echo "$header" | _egrep_o "^HTTP[^ ]* .*$" | cut -d " " -f 2-100 | tr -d "\f\n")"
  code="$(echo "$status" | _egrep_o "^[0-9]*")"
  if [ "$code" -ge 400 ] || _contains "$response" "\"error\"" || _contains "$response" "invalid_client"; then
    _err "error $status"
    _err "\n$response"
    _debug "\n$header"
    return 2
  fi

  _debug2 response "$response"
  return 0
}
