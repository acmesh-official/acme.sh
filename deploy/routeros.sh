#!/usr/bin/env sh

# Here is a script to deploy cert to routeros router.
# Deploy the cert to remote routeros
#
# ```sh
# acme.sh --deploy -d ftp.example.com --deploy-hook routeros
# ```
#
# Before you can deploy the certificate to router os, you need
# to add the id_rsa.pub key to the routeros and assign a user
# to that key.
#
# The user need to have access to ssh, ftp, read and write.
#
# There are no need to enable ftp service for the script to work,
# as they are transmitted over SCP, however ftp is needed to store
# the files on the router.
#
# Then you need to set the environment variables for the
# deploy script to work.
#
# ```sh
# export ROUTER_OS_USERNAME=certuser
# export ROUTER_OS_HOST=router.example.com
#
# acme.sh --deploy -d ftp.example.com --deploy-hook routeros
# ```
#
# The deploy script will remove previously deployed certificates,
# and it does this with an assumption on how RouterOS names imported
# certificates, adding a "cer_0" suffix at the end. This is true for
# versions 6.32 -> 6.41.3, but it is not guaranteed that it will be
# true for future versions when upgrading.
#
# If the router have other certificates with the same name as the one
# beeing deployed, then this script will remove those certificates.
#
# At the end of the script, the services that use those certificates
# could be updated. Currently only the www-ssl service is beeing
# updated, but more services could be added.
#
# For instance:
# ```sh
# export ROUTER_OS_ADDITIONAL_SERVICES="/ip service set api-ssl certificate=$_cdomain.cer_0"
# ```
#
# One optional thing to do as well is to create a script that updates
# all the required services and run that script in a single command.
#
# returns 0 means success, otherwise error.

########  Public functions #####################

#domain keyfile certfile cafile fullchain
routeros_deploy() {
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

  if [ -z "$ROUTER_OS_HOST" ]; then
    _debug "Using _cdomain as ROUTER_OS_HOST, please set if not correct."
    ROUTER_OS_HOST="$_cdomain"
  fi

  if [ -z "$ROUTER_OS_USERNAME" ]; then
    _err "Need to set the env variable ROUTER_OS_USERNAME"
    return 1
  fi

  if [ -z "$ROUTER_OS_ADDITIONAL_SERVICES" ]; then
    _debug "Not enabling additional services"
    ROUTER_OS_ADDITIONAL_SERVICES=""
  fi

  _info "Trying to push key '$_ckey' to router"
  scp "$_ckey" "$ROUTER_OS_USERNAME@$ROUTER_OS_HOST:$_cdomain.key"
  _info "Trying to push cert '$_cfullchain' to router"
  scp "$_cfullchain" "$ROUTER_OS_USERNAME@$ROUTER_OS_HOST:$_cdomain.cer"
  # shellcheck disable=SC2029
  ssh "$ROUTER_OS_USERNAME@$ROUTER_OS_HOST" bash -c "'

/certificate remove $_cdomain.cer_0

/certificate remove $_cdomain.cer_1

delay 1

/certificate import file-name=$_cdomain.cer passphrase=\"\"

/certificate import file-name=$_cdomain.key passphrase=\"\"

delay 1

/file remove $_cdomain.cer

/file remove $_cdomain.key

delay 2

/ip service set www-ssl certificate=$_cdomain.cer_0
$ROUTER_OS_ADDITIONAL_SERVICES

'"
  return 0
}
