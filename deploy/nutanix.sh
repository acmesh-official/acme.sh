#!/usr/bin/env sh

#Here is a script to deploy cert to nutanix prism server.

#returns 0 means success, otherwise error.

# export NUTANIX_USER=""  # required
# export NUTANIX_PASS=""  # required
# export NUTANIX_HOST=""  # required

#domain keyfile certfile cafile fullchain
nutanix_deploy() {
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

  _info "Deploying to $NUTANIX_HOST"

  # NUTANIX ENV VAR check
  if [ -z "$NUTANIX_USER" ] || [ -z "$NUTANIX_PASS" ] || [ -z "$NUTANIX_HOST" ]; then
    _debug "No ENV variables found lets check for saved variables"
    _getdeployconf NUTANIX_USER
    _getdeployconf NUTANIX_PASS
    _getdeployconf NUTANIX_HOST
    _nutanix_user=$NUTANIX_USER
    _nutanix_pass=$NUTANIX_PASS
    _nutanix_host=$NUTANIX_HOST
    if [ -z "$_nutanix_user" ] && [ -z "$_nutanix_pass" ] && [ -z "$_nutanix_host" ]; then
      _err "No host, user and pass found.. If this is the first time deploying please set NUTANIX_HOST, NUTANIX_USER and NUTANIX_PASS in environment variables. Delete them after you have succesfully deployed certs."
      return 1
    else
      _debug "Using saved env variables."
    fi
  else
    _debug "Detected ENV variables to be saved to the deploy conf."
    # Encrypt and save user
    _savedeployconf NUTANIX_USER "$NUTANIX_USER" 1
    _savedeployconf NUTANIX_PASS "$NUTANIX_PASS" 1
    _savedeployconf NUTANIX_HOST "$NUTANIX_HOST" 1
    _nutanix_user="$NUTANIX_USER"
    _nutanix_pass="$NUTANIX_PASS"
    _nutanix_host="$NUTANIX_HOST"
  fi
  curl --silent --fail --user "$_nutanix_user:$_nutanix_pass" -F caChain=@"$_cca" -F cert=@"$_ccert" -F key=@"$_ckey" -F keyType=RSA_2048 -k https://"$_nutanix_host":9440/PrismGateway/services/rest/v1/keys/pem/import >/dev/null
  return $?
}
