#!/usr/bin/env sh

# Script to deploy certificates to by executing a script
#
# The script is called with 5 arguments, in the following order:
# - Domain
# - Private key file path
# - Certificate file path
# - CA certificate file path
# - Full chain certificate file path
#
# Only a single environment variable needs to be set - the path
# to the script itself:
# export DEPLOY_SCRIPT_PATH="/path/to/script.py"

########  Public functions #####################

#domain keyfile certfile cafile fullchain
script_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"

  if [ -f "$DOMAIN_CONF" ]; then
    # shellcheck disable=SC1090
    . "$DOMAIN_CONF"
  fi

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"

  # SCRIPT_PATH is required.
  if [ -z "$DEPLOY_SCRIPT_PATH" ]; then
    if [ -z "$Le_Deploy_script_path" ]; then
      _err "DEPLOY_SCRIPT_PATH not defined."
      return 1
    fi
  else
    Le_Deploy_script_path="$DEPLOY_SCRIPT_PATH"
    _savedomainconf Le_Deploy_script_path "$Le_Deploy_script_path"
  fi

  _deploy_script_path=$Le_Deploy_script_path
  $_deploy_script_path "$@"
}
