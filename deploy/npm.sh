#!/usr/bin/env sh

# Deploy-hook to deploy certificate and key to nginx proxy manager/NPM Plus using
# REST API
#
# Environment variables to be utilized are as follows:
#
# DEPLOY_NPM_HOST       - host/IP address of NPM admin panel (example.com, 192.168.1.1, etc.)
# DEPLOY_NPM_PORT       - port number of NPM admin panel (80, 443, 8443, etc.)
# DEPLOY_NPM_PROTOCOL   - protocol to connect to NPM admin panel (http/https)
#                         (https is STRONGLY recommended)
# DEPLOY_NPM_CERTNUM    - custom certificate number to overwrite (1, 2, 3, etc.)
#                         (look it up in NPM admin panel, must already exist)
# DEPLOY_NPM_USER       - authorized user for NPM (adminuser, admin etc.)
# DEPLOY_NPM_PASSWORD   - authorized user's password for NPM (MySecurePassword, etc.)

########  Public functions #####################

#domain keyfile certfile cafile fullchain
npm_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"
  _cpfx="$6"

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"
  _debug _cpfx "$_cpfx"

  _getdeployconf DEPLOY_NPM_HOST
  _getdeployconf DEPLOY_NPM_PORT
  _getdeployconf DEPLOY_NPM_PROTOCOL
  _getdeployconf DEPLOY_NPM_CERTNUM
  _getdeployconf DEPLOY_NPM_USER
  _getdeployconf DEPLOY_NPM_PASSWORD

  if [ -z "$DEPLOY_NPM_HOST" ]; then
    _err "DEPLOY_NPM_HOST must be defined"
    return 1
  fi
  if [ -z "$DEPLOY_NPM_PORT" ]; then
    _err "DEPLOY_NPM_PORT must be defined"
    return 1
  fi
  if [ "$DEPLOY_NPM_PROTOCOL" != "https" ] && [ "$DEPLOY_NPM_PROTOCOL" != "http" ]; then
    _err "DEPLOY_NPM_PROTOCOL must be either http or https"
    return 1
  fi
  if [ -z "$DEPLOY_NPM_CERTNUM" ]; then
    _err "DEPLOY_NPM_CERTNUM must be defined"
    return 1
  fi
  if [ -z "$DEPLOY_NPM_USER" ]; then
    _err "DEPLOY_NPM_USER must be defined"
    return 1
  fi
  if [ -z "$DEPLOY_NPM_PASSWORD" ]; then
    _err "DEPLOY_NPM_PASSWORD must be defined"
    return 1
  fi

  _debug "DEPLOY_NPM_USER=$DEPLOY_NPM_USER"
  _secure_debug DEPLOY_NPM_PASSWORD "$DEPLOY_NPM_PASSWORD"
  _info "Authenticating to NPM and fetching temporary API token"
  _npm_token_raw=$(curl -f -k -s -X POST "$DEPLOY_NPM_PROTOCOL://$DEPLOY_NPM_HOST:$DEPLOY_NPM_PORT/api/tokens" -H "Content-Type: application/json" -d '{"identity":"'"$DEPLOY_NPM_USER"'","secret":"'"$DEPLOY_NPM_PASSWORD"'"}' -D -)
  _debug _npm_token_raw "$_npm_token_raw"
  _npm_token=$(printf '%s\n' "$_npm_token_raw" | sed -n 's/.*__Host-Http-token=\([^;]*\).*/\1/p')
  if [ "$_npm_token" = "" ]; then
    _err "Failed to retrieve a token (check your credentials?)"
    return 1
  else
    _secure_debug _npm_token "$_npm_token"
    _info "API token retrieved."
  fi

  _info "Deploying to NPM"
  _npm_error=$(curl -s -k -X POST "$DEPLOY_NPM_PROTOCOL://$DEPLOY_NPM_HOST:$DEPLOY_NPM_PORT/api/nginx/certificates/$DEPLOY_NPM_CERTNUM/upload" -H "Cookie: __Host-Http-token=$_npm_token" -F "certificate=@$_cfullchain" -F "certificate_key=@$_ckey")
  if [ "$_npm_error" != "{}" ]; then
    _err "Failed to upload certificates: $_npm_error"
    return 1
  fi

  _savedeployconf DEPLOY_NPM_HOST "$DEPLOY_NPM_HOST"
  _savedeployconf DEPLOY_NPM_PORT "$DEPLOY_NPM_PORT"
  _savedeployconf DEPLOY_NPM_PROTOCOL "$DEPLOY_NPM_PROTOCOL"
  _savedeployconf DEPLOY_NPM_CERTNUM "$DEPLOY_NPM_CERTNUM"
  _savedeployconf DEPLOY_NPM_USER "$DEPLOY_NPM_USER"
  _savedeployconf DEPLOY_NPM_PASSWORD "$DEPLOY_NPM_PASSWORD" "base64"

  _info "$(__green "'npm' deploy success")"
  return 0
}
