#!/bin/bash

# Here is a script to deploy cert to ikuai using curl
#
# it requires following environment variables:
#
# IKUAI_SCHEME="http"           - http or https , defaults to "http"
# IKUAI_HOSTNAME="localhost"    - host , defaults to "192.168.9.1"
# IKUAI_PORT="80"               - port , defaults to "80"
# IKUAI_USERNAME="admin"        - username , defaults to "admin"
# IKUAI_PASSWORD="yourPassword" - password
#
#returns 0 means success, otherwise error.
#
########  Public functions #####################
#
#domain keyfile certfile cafile fullchain
ikuai_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"

  [ -n "$IKUAI_SCHEME" ] || IKUAI_SCHEME="http"
  [ -n "$IKUAI_HOSTNAME" ] || IKUAI_HOSTNAME="192.168.9.1"
  [ -n "$IKUAI_PORT" ] || IKUAI_PORT=80
  [ -n "$IKUAI_USERNAME" ] || IKUAI_USERNAME="admin"

  # Get deploy conf
  _getdeployconf IKUAI_SCHEME
  _getdeployconf IKUAI_HOSTNAME
  _getdeployconf IKUAI_PORT
  _getdeployconf IKUAI_USERNAME
  _getdeployconf IKUAI_PASSWORD

  if [ -z "$IKUAI_HOSTNAME" ] || [ -z "$IKUAI_USERNAME" ] || [ -z "$IKUAI_PASSWORD" ]; then
    _err "IKUAI_HOSTNAME ,IKUAI_USERNAME and IKUAI_PASSWORD is required ."
    return 1
  fi

  _debug2 IKUAI_SCHEME "$IKUAI_SCHEME"
  _debug2 IKUAI_HOSTNAME "$IKUAI_HOSTNAME"
  _debug2 IKUAI_PORT "$IKUAI_PORT"
  _debug2 IKUAI_USERNAME "$IKUAI_USERNAME"
  _secure_debug2 IKUAI_PASSWORD "$IKUAI_PASSWORD"

  _info "Login to ikuai ..."
  _ikuai_url="$IKUAI_SCHEME://$IKUAI_HOSTNAME:$IKUAI_PORT"
  _pass_md5="$(printf "%s" "$IKUAI_PASSWORD" | _digest md5 hex | _lower_case)"
  _pass_salt="$(printf "salt_11%s" "$IKUAI_PASSWORD" | _base64)"
  _login_req="{\"username\":\"$IKUAI_USERNAME\",\"passwd\":\"$_pass_md5\",\"pass\":\"$_pass_salt\",\"remember_password\":\"\"}"

  _debug2 _ikuai_url "$_ikuai_url"

  _response=$(_post "$_login_req" "$_ikuai_url/Action/login" "" "POST" "application/json")

  if ! _contains "$_response" "ErrMsg"; then
    _err "Failed to login to ikuai : $_response"
    return 1
  fi
  _err_msg="$(printf "%s" "$_response" | _normalizeJson | _egrep_o '"ErrMsg":"[^"]*"' | cut -d'"' -f4)"
  # check ErrMsg
  if [ "$_err_msg" != "Success" ]; then
    _err "Failed to login to ikuai: $_err_msg"
    return 1
  fi
  # check cookie
  _cookie="$(grep -i '^set-cookie:' "$HTTP_HEADER" | _head_n 1 | cut -d " " -f 2)"
  if [ -z "$_cookie" ]; then
    _err "Fail to get the cookie."
    return 1
  fi
  _info "Login to ikuai success ,now save the config ... "

  # Save the config
  _savedeployconf IKUAI_SCHEME "$IKUAI_SCHEME"
  _savedeployconf IKUAI_HOSTNAME "$IKUAI_HOSTNAME"
  _savedeployconf IKUAI_PORT "$IKUAI_PORT"
  _savedeployconf IKUAI_USERNAME "$IKUAI_USERNAME"
  _savedeployconf IKUAI_PASSWORD "$IKUAI_PASSWORD"

  # Set cookie header
  _H1="Cookie: $_cookie username=$IKUAI_USERNAME; login=1"

  _info "Deploy the cert to ikuai ... "

  # Should replace \n to @ ," " to #
  _cert_content_single_line="$(<"$_ccert" tr '\n' '@' | tr ' ' '#')"
  _key_content_single_line="$(<"$_ckey" tr '\n' '@' | tr ' ' '#')"

  _debug2 _cert_content_single_line "$_cert_content_single_line"
  _debug2 _key_content_single_line "$_key_content_single_line"

  _key_manager_req="{\"func_name\":\"key_manager\",\"action\":\"save\",\"param\":{\"ca\":\"$_cert_content_single_line\",\"key\":\"$_key_content_single_line\",\"id\":1,\"enabled\":\"yes\",\"comment\":\"\"}}"
  _response=$(_post "$_key_manager_req" "$_ikuai_url/Action/call" "" "POST" "application/json")

  _err_msg="$(printf "%s" "$_response" | _normalizeJson | _egrep_o '"ErrMsg":"[^"]*"' | cut -d'"' -f4)"

  if ! _contains "$_response" "ErrMsg"; then
    _err "Failed to save cert to ikuai : $_response"
    return 1
  fi
  # check ErrMsg
  if [ "$_err_msg" != "Success" ]; then
    _err "Failed to save cert to ikuai: $_err_msg"
    return 1
  fi
  _info "Deploy the cert to ikuai success ,now enjoy it :>! "

  return 0
}
