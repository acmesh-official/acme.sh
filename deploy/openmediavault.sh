#!/usr/bin/env sh

# This deploy hook is tested on OpenMediaVault 5.x. It supports both local and remote deployment.
# The way it works is that if a cert with the matching domain name is not found, it will firstly create a dummy cert to get its uuid, and then replace it with your cert.
#
# DEPLOY_OMV_WEBUI_ADMIN - This is OMV web gui admin account. Default value is admin. It's required as the user parameter (-u) for the omv-rpc command.
# DEPLOY_OMV_HOST and DEPLOY_OMV_SSH_USER are optional. They are used for remote deployment through ssh (support public key authentication only). Per design, OMV web gui admin doesn't have ssh permission, so another account is needed for ssh.
#
# returns 0 means success, otherwise error.

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

  _getdeployconf DEPLOY_OMV_WEBUI_ADMIN

  if [ -z "$DEPLOY_OMV_WEBUI_ADMIN" ]; then
    DEPLOY_OMV_WEBUI_ADMIN="admin"
  fi

  _savedeployconf DEPLOY_OMV_WEBUI_ADMIN "$DEPLOY_OMV_WEBUI_ADMIN"

  _getdeployconf DEPLOY_OMV_HOST
  _getdeployconf DEPLOY_OMV_SSH_USER

  if [ -n "$DEPLOY_OMV_HOST" ] && [ -n "$DEPLOY_OMV_SSH_USER" ]; then
    _info "[OMV deploy-hook] Deploy certificate remotely through ssh."
    _savedeployconf DEPLOY_OMV_HOST "$DEPLOY_OMV_HOST"
    _savedeployconf DEPLOY_OMV_SSH_USER "$DEPLOY_OMV_SSH_USER"
  else
    _info "[OMV deploy-hook] Deploy certificate locally."
  fi

  if [ -n "$DEPLOY_OMV_HOST" ] && [ -n "$DEPLOY_OMV_SSH_USER" ]; then

    _command="omv-rpc -u $DEPLOY_OMV_WEBUI_ADMIN 'CertificateMgmt' 'getList' '{\"start\": 0, \"limit\": -1}' | jq -r '.data[] | select(.name==\"/CN='$_cdomain'\") | .uuid'"
    # shellcheck disable=SC2029
    _uuid=$(ssh "$DEPLOY_OMV_SSH_USER@$DEPLOY_OMV_HOST" "$_command")
    _debug _command "$_command"

    if [ -z "$_uuid" ]; then
      _info "[OMV deploy-hook] Domain $_cdomain has no certificate in openmediavault, creating it!"
      _command="omv-rpc -u $DEPLOY_OMV_WEBUI_ADMIN 'CertificateMgmt' 'create' '{\"cn\": \"test.example.com\", \"size\": 4096, \"days\": 3650, \"c\": \"\", \"st\": \"\", \"l\": \"\", \"o\": \"\", \"ou\": \"\", \"email\": \"\"}' | jq -r '.uuid'"
      # shellcheck disable=SC2029
      _uuid=$(ssh "$DEPLOY_OMV_SSH_USER@$DEPLOY_OMV_HOST" "$_command")
      _debug _command "$_command"

      if [ -z "$_uuid" ]; then
        _err "[OMV deploy-hook] An error occured while creating the certificate"
        return 1
      fi
    fi

    _info "[OMV deploy-hook] Domain $_cdomain has uuid: $_uuid"
    _fullchain=$(jq <"$_cfullchain" -aRs .)
    _key=$(jq <"$_ckey" -aRs .)

    _debug _fullchain "$_fullchain"
    _debug _key "$_key"

    _info "[OMV deploy-hook] Updating key and certificate in openmediavault"
    _command="omv-rpc -u $DEPLOY_OMV_WEBUI_ADMIN 'CertificateMgmt' 'set' '{\"uuid\":\"$_uuid\", \"certificate\":$_fullchain, \"privatekey\":$_key, \"comment\":\"acme.sh deployed $(date)\"}'"
    # shellcheck disable=SC2029
    _result=$(ssh "$DEPLOY_OMV_SSH_USER@$DEPLOY_OMV_HOST" "$_command")

    _debug _command "$_command"
    _debug _result "$_result"

    _command="omv-rpc -u $DEPLOY_OMV_WEBUI_ADMIN 'WebGui' 'setSettings' \$(omv-rpc -u $DEPLOY_OMV_WEBUI_ADMIN 'WebGui' 'getSettings' | jq -c '.sslcertificateref=\"$_uuid\"')"
    # shellcheck disable=SC2029
    _result=$(ssh "$DEPLOY_OMV_SSH_USER@$DEPLOY_OMV_HOST" "$_command")

    _debug _command "$_command"
    _debug _result "$_result"

    _info "[OMV deploy-hook] Asking openmediavault to apply changes... (this could take some time, hang in there)"
    _command="omv-rpc -u $DEPLOY_OMV_WEBUI_ADMIN 'Config' 'applyChanges' '{\"modules\":[], \"force\": false}'"
    # shellcheck disable=SC2029
    _result=$(ssh "$DEPLOY_OMV_SSH_USER@$DEPLOY_OMV_HOST" "$_command")

    _debug _command "$_command"
    _debug _result "$_result"

    _info "[OMV deploy-hook] Asking nginx to reload"
    _command="nginx -s reload"
    # shellcheck disable=SC2029
    _result=$(ssh "$DEPLOY_OMV_SSH_USER@$DEPLOY_OMV_HOST" "$_command")

    _debug _command "$_command"
    _debug _result "$_result"

  else

    # shellcheck disable=SC2086
    _uuid=$(omv-rpc -u $DEPLOY_OMV_WEBUI_ADMIN 'CertificateMgmt' 'getList' '{"start": 0, "limit": -1}' | jq -r '.data[] | select(.name=="/CN='$_cdomain'") | .uuid')
    if [ -z "$_uuid" ]; then
      _info "[OMV deploy-hook] Domain $_cdomain has no certificate in openmediavault, creating it!"
      # shellcheck disable=SC2086
      _uuid=$(omv-rpc -u $DEPLOY_OMV_WEBUI_ADMIN 'CertificateMgmt' 'create' '{"cn": "test.example.com", "size": 4096, "days": 3650, "c": "", "st": "", "l": "", "o": "", "ou": "", "email": ""}' | jq -r '.uuid')

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

    _info "[OMV deploy-hook] Updating key and certificate in openmediavault"
    _command="omv-rpc -u $DEPLOY_OMV_WEBUI_ADMIN 'CertificateMgmt' 'set' '{\"uuid\":\"$_uuid\", \"certificate\":$_fullchain, \"privatekey\":$_key, \"comment\":\"acme.sh deployed $(date)\"}'"
    _result=$(eval "$_command")

    _debug _command "$_command"
    _debug _result "$_result"

    _command="omv-rpc -u $DEPLOY_OMV_WEBUI_ADMIN 'WebGui' 'setSettings' \$(omv-rpc -u $DEPLOY_OMV_WEBUI_ADMIN 'WebGui' 'getSettings' | jq -c '.sslcertificateref=\"$_uuid\"')"
    _result=$(eval "$_command")

    _debug _command "$_command"
    _debug _result "$_result"

    _info "[OMV deploy-hook] Asking openmediavault to apply changes... (this could take some time, hang in there)"
    _command="omv-rpc -u $DEPLOY_OMV_WEBUI_ADMIN 'Config' 'applyChanges' '{\"modules\":[], \"force\": false}'"
    _result=$(eval "$_command")

    _debug _command "$_command"
    _debug _result "$_result"

    _info "[OMV deploy-hook] Asking nginx to reload"
    _command="nginx -s reload"
    _result=$(eval "$_command")

    _debug _command "$_command"
    _debug _result "$_result"

  fi

  return 0
}
