#!/bin/bash

################################################################
###
###  A script to deploy Let's Encrypt certificate
###  on Edgemax routers.
###
################################################################

#This file name is "edgemax.sh"
#So, here must be a method   edgemax_deploy()
#Which will be called by acme.sh to deploy the cert
#returns 0 means success, otherwise error.

########  Public functions #####################
function atexit() {
 #closes CLI session
 cli-shell-api teardownSession
 _debug EXITCODE: $1
 return $1
}


#domain keyfile certfile cafile fullchain
edgemax_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"

  ### 'lighttpd_pem' - certificate file configured for your Edgemax GUI

  lighttpd_pem=/config/auth/le-cert.pem

  _info  "$(__green "EdgeMax Certificate Path: $lighttpd_pem")"
  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"
  _info "Generating PEM file for lighttpd"
  sudo sh -c "cat ${_ccert} ${_ckey} > ${lighttpd_pem}"

  _info  "$(__green "Checking EdgeMax Config for SSL Settings: $lighttpd_pem")"
  vals=$( cli-shell-api returnEffectiveValue service gui cert-file)
  certfile=$vals
  if [ "$lighttpd_pem" != "$certfile" ]; then
   _debug "Current Edgemax Certfile" "$certfile"
   _info "Certfile is not set to $lighttpd_pem"

   # Obtain session environment
   session_env=$(cli-shell-api getSessionEnv $PPID)
   eval $session_env
    
   # Setup the session
   cli-shell-api setupSession

   # Verify Session Started
   cli-shell-api inSession
   if [ $? -ne 0 ]; then
    _err "Something went wrong starting CLI Session!"
    atexit 1
   fi
   SET=${vyatta_sbindir}/my_set
   COMMIT=${vyatta_sbindir}/my_commit
   SAVE=${vyatta_sbindir}/vyatta-save-config.pl
   _info "Setting Certificate parameter."
   $SET service gui cert-file /config/auth/le-cert.pem
   $COMMIT
   $SAVE
   else
    _info "EdgeMax cert-file already set to $lighttpd_pem"
   fi
  _info Restarting lighttpd
  sudo kill -SIGTERM $(cat /var/run/lighttpd.pid)
  sudo /usr/sbin/lighttpd -f /etc/lighttpd/lighttpd.conf

 atexit 0

}
