#!/usr/bin/bash

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

  if [ -z "$DEPLOY_OMV_USER" ]
  then
    DEPLOY_OMV_USER="admin"
  fi

  _uuid=$(omv-rpc -u "$DEPLOY_OMV_USER" 'CertificateMgmt' 'getList' '{"start": 0, "limit": -1}' | jq -r '.data[] | select(.name=="/CN='$_cdomain'") | .uuid')
  if [ -z "$_uuid" ]
  then
    echo "Domain $_cdomain has no certificate in Openmediavault, creating it!"
    _uuid=$(omv-rpc -u "$DEPLOY_OMV_USER" 'CertificateMgmt' 'create' '{"cn": "test.example.com", "size": 4096, "days": 3650, "c": "", "st": "", "l": "", "o": "", "ou": "", "email": ""}' | jq -r '.uuid')

    if [ -z "$_uuid" ]
    then
      echo "An error occured while creating the certificate"
      return 1
    fi
  fi

  echo "Domain $_cdomain has uuid: $_uuid"
  _fullchain=$(cat "$_cfullchain" | jq -aRs .)
  _key=$(cat "$_ckey" | jq -aRs .)
  _date=$(echo "$(date)")

#  echo "$_fullchain"
#  echo "$_key"

  echo "Updating key and certificate in Openmediavault"
  _command="omv-rpc -u $DEPLOY_OMV_USER 'CertificateMgmt' 'set' '{\"uuid\":\"$_uuid\", \"certificate\":$_fullchain, \"privatekey\":$_key, \"comment\":\"acme.sh deployed $_date\"}'"
  _result=$(eval "$_command")

#  echo "$_command"
#  echo "$_result"

  echo "Asking Openmediavault to apply changes... (this could take some time, hang in there)"
  _command="omv-rpc -u $DEPLOY_OMV_USER 'Config' 'applyChanges' '{\"modules\":[\"certificates\"], \"force\": false}'"
  _result=$(eval "$_command")

#  echo "$_command"
#  echo "$_result"

  return 0

}
