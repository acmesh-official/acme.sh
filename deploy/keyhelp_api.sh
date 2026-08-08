#!/usr/bin/env sh

keyhelp_api_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"

  # Read config from saved values or env
  _getdeployconf DEPLOY_KEYHELP_HOST
  _getdeployconf DEPLOY_KEYHELP_API_KEY
  _getdeployconf DEPLOY_KEYHELP_NAME

  _debug DEPLOY_KEYHELP_HOST "$DEPLOY_KEYHELP_HOST"
  _secure_debug DEPLOY_KEYHELP_API_KEY "$DEPLOY_KEYHELP_API_KEY"
  _debug DEPLOY_KEYHELP_NAME "$DEPLOY_KEYHELP_NAME"

  if [ -z "$DEPLOY_KEYHELP_HOST" ]; then
    _err "KeyHelp host not found, please define DEPLOY_KEYHELP_HOST."
    return 1
  fi
  if [ -z "$DEPLOY_KEYHELP_API_KEY" ]; then
    _err "KeyHelp api key not found, please define DEPLOY_KEYHELP_API_KEY."
    return 1
  fi

  if [ -z "$DEPLOY_KEYHELP_NAME" ]; then
    _keyhelp_name="$_cdomain"
  else
    _keyhelp_name="$DEPLOY_KEYHELP_NAME"
  fi

  # Save current values
  _savedeployconf DEPLOY_KEYHELP_HOST "$DEPLOY_KEYHELP_HOST"
  _savedeployconf DEPLOY_KEYHELP_API_KEY "$DEPLOY_KEYHELP_API_KEY"
  _savedeployconf DEPLOY_KEYHELP_NAME "$DEPLOY_KEYHELP_NAME"

  _request_cert="$(tr '\n' ':' <"$_ccert" | sed 's/:/\\n/g')"
  _request_ca="$(tr '\n' ':' <"$_cca" | sed 's/:/\\n/g')"

  _keyhelp_name_json_escaped="$(printf "%s" "$_keyhelp_name" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  _keyhelp_name_url_encoded="$(printf "%s" "$_keyhelp_name" | _url_encode)"

  _keyhelp_put_body="{
    \"name\": \"$_keyhelp_name_json_escaped\",
    \"components\": {
      \"certificate\": \"$_request_cert\",
      \"ca_certificate\": \"$_request_ca\"
    }
  }"

  _hosts="$(echo "$DEPLOY_KEYHELP_HOST" | tr "," " ")"
  _keys="$(echo "$DEPLOY_KEYHELP_API_KEY" | tr "," " ")"
  _i=1

  for _host in $_hosts; do
    _key="$(_getfield "$_keys" "$_i" " ")"
    _i="$(_math "$_i" + 1)"

    export _H1="X-API-Key: $_key"

    _keyhelp_put_url="$_host/api/v2/certificates/name/$_keyhelp_name_url_encoded"
    if _post "$_keyhelp_put_body" "$_keyhelp_put_url" "" "PUT" "application/json" >/dev/null; then
      _code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\r\n")"
    else
      _err "Cannot make PUT request to $_keyhelp_put_url"
      return 1
    fi

    if [ "$_code" = "404" ]; then
      _info "$_keyhelp_name not found, creating new entry at $_host"

      if [ ! -s "$_ckey" ]; then
        _err "Private key file $_ckey not found. It is required to create a new certificate entry."
        return 1
      fi
      _request_key="$(tr '\n' ':' <"$_ckey" | sed 's/:/\\n/g')"
      _keyhelp_post_body="{
        \"name\": \"$_keyhelp_name_json_escaped\",
        \"components\": {
          \"private_key\": \"$_request_key\",
          \"certificate\": \"$_request_cert\",
          \"ca_certificate\": \"$_request_ca\"
        }
      }"

      _keyhelp_post_url="$_host/api/v2/certificates"
      if _post "$_keyhelp_post_body" "$_keyhelp_post_url" "" "POST" "application/json" >/dev/null; then
        _code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\r\n")"
      else
        _err "Cannot make POST request to $_keyhelp_post_url"
        return 1
      fi
    fi

    if _startswith "$_code" "2"; then
      _info "$_keyhelp_name set at $_host"
    else
      _err "HTTP status code is $_code"
      return 1
    fi
  done

  return 0
}
