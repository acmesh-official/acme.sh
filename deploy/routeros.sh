#!/bin/bash

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
# deploy script to work. It will store those in the domainconf.
# So there is no need to set them every time.
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
# updated. You can prevent this by setting the following enviroment
# variable: `export ROUTER_OS_WEB_SERVICE="no"`.

# You can add more services to 
#, but more services could be added.
#
# For instance:
# ```sh
# export ROUTER_OS_ADDITIONAL_SERVICES="/ip service set api-ssl certificate=$_cdomain.cer_0"
# ```
#
# To set the ssl-certificate for a hotspot profile the following command
# is useful: 
# ```sh
# /ip hotspot profile set [find dns-name=hs.example.com] ssl-certificate=hs.example.com.cer_0
# ```
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

  # ROUTER_OS_USERNAME is required to login to remote host.
  if [ -z "$ROUTER_OS_USERNAME" ]; then
    if [ -z "$Le_router_os_username" ]; then
      _err "Need to set the env variable ROUTER_OS_USERNAME"
      return 1
    fi
  else
    _info "saving ROUTER_OS_USERNAME in the domainconf"
    Le_router_os_username="$ROUTER_OS_USERNAME"
    _savedomainconf Le_router_os_username "$Le_router_os_username"
  fi

  # ROUTER_OS_HOST is optional. If not provided then use _cdomain
  if [ -n "$ROUTER_OS_HOST" ]; then
    _info "saving ROUTER_OS_HOST in the domainconf"
    Le_router_os_host="$ROUTER_OS_HOST"
    _savedomainconf Le_router_os_host "$Le_router_os_host"
  elif [ -z "$Le_router_os_host" ]; then
    _debug "Using _cdomain as ROUTER_OS_HOST, please set if not correct."
    Le_router_os_host="$_cdomain"
  fi

  # ROUTER_OS_ADDITIONAL_SERVICES is optional.
  if [ -n "$ROUTER_OS_ADDITIONAL_SERVICES" ]; then
    _info "saving ROUTER_OS_ADDITIONAL_SERVICES in the domainconf"
    Le_router_os_additional_services="$ROUTER_OS_ADDITIONAL_SERVICES"
    _savedomainconf Le_router_os_additional_services "$Le_router_os_additional_services"
  elif [ -z "$Le_router_os_additional_services" ]; then
    _info "saving ROUTER_OS_ADDITIONAL_SERVICES in the domainconf"
    Le_router_os_additional_services=""
    _savedomainconf Le_router_os_additional_services "$Le_router_os_additional_services"
  fi

  # ROUTER_OS_WEB_SERVICE is optional. Default is yes
  if [ "$ROUTER_OS_WEB_SERVICE" = "no" ]; then
    _debug "don't set the certificate for www-ssl service, saving this in the domainconf."
    Le_router_os_web_service="no"
    _savedomainconf Le_router_os_web_service "$Le_router_os_web_service"
  elif [ "$ROUTER_OS_WEB_SERVICE" = "yes" ] || [ -z "$Le_router_os_web_service" ]; then
    _debug "setting the certificate for www-ssl service, saving this in the domainconf."
    Le_router_os_web_service="yes"
    _savedomainconf Le_router_os_web_service "$Le_router_os_web_service"
  fi
  
  router_os_services=""

  if [ "$Le_router_os_web_service" = "yes" ]; then
    router_os_services="$router_os_services \r\n /ip service set www-ssl certificate=$_cdomain.cer_0"
  fi

  if [ ! -z "$Le_router_os_additional_services" ]; then
    router_os_services="$router_os_services \r\n $Le_router_os_additional_services"
  fi

  _info "Trying to push key '$_ckey' to router"
  scp "$_ckey" "$Le_router_os_username@$Le_router_os_host:$_cdomain.key"
  if [ $? -ne 0 ]; then
    _err "pushing key '$_ckey' wasn't successull. Stopping here"
    return 1
  fi

  _info "Trying to push cert '$_cfullchain' to router"
  scp "$_cfullchain" "$Le_router_os_username@$Le_router_os_host:$_cdomain.cer"
  if [ $? -ne 0 ]; then
    _err "pushing key '$_ckey' wasn't successull. Stopping here"
    return 1
  fi

  DEPLOY_SCRIPT_CMD="/system script add name=\"LE Cert Deploy - $_cdomain\" owner=admin policy=ftp,read,write,password,sensitive \
source=\"## generated by routeros deploy script in acme.sh\r\n\
\r\n /certificate remove [ find name=$_cdomain.cer_0 ]\
\r\n /certificate remove [ find name=$_cdomain.cer_1 ]\
\r\n delay 1\
\r\n /certificate import file-name=$_cdomain.cer passphrase=\\\"\\\"\
\r\n /certificate import file-name=$_cdomain.key passphrase=\\\"\\\"\
\r\n delay 1\
\r\n /file remove $_cdomain.cer\
\r\n /file remove $_cdomain.key\
\r\n delay 2\
$router_os_services\""


  # shellcheck disable=SC2029
  ssh "$Le_router_os_username@$Le_router_os_host" "$DEPLOY_SCRIPT_CMD"
  # shellcheck disable=SC2029
  ssh "$Le_router_os_username@$Le_router_os_host" "/system script run \"LE Cert Deploy - $_cdomain\""
  # shellcheck disable=SC2029
  ssh "$Le_router_os_username@$Le_router_os_host" "/system script remove \"LE Cert Deploy - $_cdomain\""

  return 0
}
