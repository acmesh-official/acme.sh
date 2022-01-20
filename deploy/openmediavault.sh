#!/usr/bin/env sh

########  Public functions #####################

#domain keyfile certfile cafile fullchain
openmediavault_deploy() {
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

  if [ -z "$DEPLOY_OMV_USER" ]; then
    DEPLOY_OMV_USER="admin"
  fi

  # shellcheck disable=SC2086
  _uuid=$(omv-rpc -u "$DEPLOY_OMV_USER" 'CertificateMgmt' 'getList' '{"start": 0, "limit": -1}' | jq -r '.data[] | select(.name=="/CN='$_cdomain'") | .uuid')
  if [ -z "$_uuid" ]; then
    _info "[OMV deploy-hook] Domain $_cdomain has no certificate in Openmediavault, creating it!"
    _uuid=$(omv-rpc -u "$DEPLOY_OMV_USER" 'CertificateMgmt' 'create' '{"cn": "test.example.com", "size": 4096, "days": 3650, "c": "", "st": "", "l": "", "o": "", "ou": "", "email": ""}' | jq -r '.uuid')

    if [ -z "$_uuid" ]; then
      _err "[OMB deploy-hook] An error occured while creating the certificate"
      return 1
    fi
  fi

  _info "[OMV deploy-hook] Domain $_cdomain has uuid: $_uuid"
  _fullchain=$(jq <"$_cfullchain" -aRs .)
  _key=$(jq <"$_ckey" -aRs .)

  _debug _fullchain "$_fullchain"
  _debug _key "$_key"

  _info "[OMV deploy-hook] Updating key and certificate in Openmediavault"
  _command="omv-rpc -u $DEPLOY_OMV_USER 'CertificateMgmt' 'set' '{\"uuid\":\"$_uuid\", \"certificate\":$_fullchain, \"privatekey\":$_key, \"comment\":\"acme.sh deployed $(date)\"}'"
  _result=$(eval "$_command")

  _debug _command "$_command"
  _debug _result "$_result"

  _info "[OMV deploy-hook] Asking Openmediavault to apply changes... (this could take some time, hang in there)"
  _command="omv-rpc -u $DEPLOY_OMV_USER 'Config' 'applyChanges' '{\"modules\":[\"certificates\"], \"force\": false}'"
  _result=$(eval "$_command")

  _debug _command "$_command"
  _debug _result "$_result"

  return 0
}
