#!/bin/bash

#Here is a script to deploy cert to opengear operations manager.

#returns 0 means success, otherwise error.

# Note that SSH must be able to login to remote host without a password...
# The user must have sudo-access without password
#
# SSH Keys must have been exchanged with the remote host.  Validate and
# test that you can login to USER@SERVER from the host running acme.sh before
# using this script.

# export OPENGEAR_USER=""        # required
# export OPENGEAR_HOST="om1234"  # defaults to domain name

Le_Deploy_ssh_cmd="ssh"

#domain keyfile certfile cafile fullchain
opengear_deploy() {
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

  # OPENGEAR ENV VAR check
  if [ -z "$OPENGEAR_HOST" ]; then
    # HOST is not set in environment, check for saved variable
    _getdeployconf OPENGEAR_HOST
    _opengear_host=$OPENGEAR_HOST
  fi
  if [ -z "$_opengear_host" ]; then
    _info "No host found in saved vars. Defaulting to domain: $_cdomain"
    _opengear_host="$_cdomain"
  fi
  if [ -z "$OPENGEAR_USER" ]; then
    _debug "USER not found in ENV variables lets check for saved variables"
    _getdeployconf OPENGEAR_USER
    _opengear_user=$OPENGEAR_USER
    if [ -z "$_opengear_user" ]; then
      _err "No user found.. If this is the first time deploying please set OPENGEAR_USER in environment variables. Delete them after you have succesfully deployed certs."
      return 1
    else
      _debug "Using saved env variables."
    fi
  else
    _debug "Detected ENV variables to be saved to the deploy conf."
    _opengear_user="$OPENGEAR_USER"
    # Encrypt and save user
    _savedeployconf OPENGEAR_USER "$_opengear_user" 1
    _savedeployconf OPENGEAR_HOST "$_opengear_host" 1
  fi
  _info "Deploying to $_opengear_host"

  _cmdstr="sudo echo -e \"set services.https.certificate =$(base64 -w0 "$_cfullchain")\nset services.https.private_key =$(base64 -w0 "$_ckey")\npush\" | /usr/bin/ogconfig-cli || \
           sudo echo -e \"set services.https.certificate =$(base64 -w0 "$_cfullchain")\nset services.https.private_key =$(base64 -w0 "$_ckey")\npush\" | /usr/unsupported/bin/ogconfig-cli"
  _info "will deploy new certificate"
  if ! _ssh_remote_cmd "$_cmdstr"; then
    return "$_err_code"
  fi

  return "$_err_code"
}

#cmd
_ssh_remote_cmd() {
  _cmd="$1"
  _secure_debug "Remote commands to execute: $_cmd"
  _info "Submitting sequence of commands to remote server by ssh"
  # quotations in bash cmd below intended.  Squash travis spellcheck error
  # shellcheck disable=SC2029
  _debug $Le_Deploy_ssh_cmd "$_opengear_user@$_opengear_host" sh -c "'$_cmd'"
  $Le_Deploy_ssh_cmd "$_opengear_user@$_opengear_host" sh -c "'$_cmd'"
  _err_code="$?"

  if [ "$_err_code" != "0" ]; then
    _err "Error code $_err_code returned from ssh"
  fi

  return $_err_code
}
