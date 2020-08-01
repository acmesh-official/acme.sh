#!/usr/bin/env bash

# Deploy script for HPE iLO4
#
# The following environment variables are
# needed for the deploy script to work:
#
# ```sh
# export HPILO_USERNAME=admin
# export HPILO_PASSWORD=secret
# export HPILO_HOST=ilo.example.com
#
# acme.sh --deploy -d ilo.example.com --deploy-hook hpilo
# ```

########  Public functions #####################

#domain keyfile certfile cafile fullchain
hpilo_deploy() {
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

  # iLO host is optional, use _cdomain if not provided
  if [ -n "$HPILO_HOST" ]; then
    Le_Deploy_ilo_host="$HPILO_HOST"
    _savedomainconf Le_Deploy_ilo_host "$Le_Deploy_ilo_host"
  elif [ -z "$Le_Deploy_ilo_host" ]; then
    _debug "Using _cdomain as iLO host, set HPILO_HOST if not correct."
    Le_Deploy_ilo_host="$_cdomain"
  fi

  # iLO username is required
  if [ -z "$HPILO_USERNAME" ]; then
    if [ -z "$Le_Deploy_ilo_username" ]; then
      _err "HPILO_USERNAME is not defined."
      return 1
    fi
  else
    Le_Deploy_ilo_username="$HPILO_USERNAME"
    _savedomainconf Le_Deploy_ilo_username "$Le_Deploy_ilo_username"
  fi

  # iLO password is required
  if [ -z "$HPILO_PASSWORD" ]; then
    if [ -z "$Le_Deploy_ilo_password" ]; then
      _err "HPILO_PASSWORD is not defined."
      return 1
    fi
  else
    Le_Deploy_ilo_password="$HPILO_PASSWORD"
    _savedomainconf Le_Deploy_ilo_password "$Le_Deploy_ilo_password"
  fi

  _info "Attempting to deploy certificate '$_ccert' to '$Le_Deploy_ilo_host'"

  curl -sS -k -X POST -H "Content-Type: application/json" -d "{ \"Action\": \"ImportCertificate\", \"Certificate\": \"$(cat $_ccert)\" }" -u $Le_Deploy_ilo_username:$Le_Deploy_ilo_password https://$Le_Deploy_ilo_host/redfish/v1/Managers/1/SecurityService/HttpsCert/
  _ret="$?"

  if [ "$_ret" != "0" ]; then
    _err "Error code $_ret returned from iLO Redfish API"
  fi

  return $_ret
}
