#!/usr/bin/env bash

# Here is a script to deploy cert to Ruckus Zone Director/Unleashed.
#
# Adapted from:
# https://ms264556.net/pages/PfSenseLetsEncryptToRuckus
#
# ```sh
# acme.sh --deploy -d ruckus.example.com --deploy-hook ruckus
# ```
#
# Then you need to set the environment variables for the
# deploy script to work.
#
# ```sh
# export RUCKUS_HOST=ruckus.example.com
# export RUCKUS_USER=myruckususername
# export RUCKUS_PASS=myruckuspassword
#
# acme.sh --deploy -d ruckus.example.com --deploy-hook ruckus
# ```
#
# returns 0 means success, otherwise error.

########  Public functions #####################

#domain keyfile certfile cafile fullchain
ruckus_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"
  _err_code=0

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"

  _getdeployconf RUCKUS_HOST
  _getdeployconf RUCKUS_USER
  _getdeployconf RUCKUS_PASS

  if [ -z "$RUCKUS_HOST" ]; then
    _debug "Using _cdomain as RUCKUS_HOST, please set if not correct."
    RUCKUS_HOST="$_cdomain"
  fi

  if [ -z "$RUCKUS_USER" ]; then
    _err "Need to set the env variable RUCKUS_USER"
    return 1
  fi

  if [ -z "$RUCKUS_PASS" ]; then
    _err "Need to set the env variable RUCKUS_PASS"
    return 1
  fi

  _savedeployconf RUCKUS_HOST "$RUCKUS_HOST"
  _savedeployconf RUCKUS_USER "$RUCKUS_USER"
  _savedeployconf RUCKUS_PASS "$RUCKUS_PASS"

  _debug RUCKUS_HOST "$RUCKUS_HOST"
  _debug RUCKUS_USER "$RUCKUS_USER"
  _debug RUCKUS_PASS "$RUCKUS_PASS"

  COOKIE_JAR=$(mktemp)
  cleanup() {
    rm $COOKIE_JAR
  }
  trap cleanup EXIT

  LOGIN_URL=$(curl https://$RUCKUS_HOST -ksSLo /dev/null -w '%{url_effective}')
  _debug LOGIN_URL "$LOGIN_URL"

  XSS=$(curl -ksSic $COOKIE_JAR $LOGIN_URL -d username=$RUCKUS_USER -d password="$RUCKUS_PASS" -d ok='Log In' | awk '/^HTTP_X_CSRF_TOKEN:/ { print $2 }' | tr -d '\040\011\012\015')
  _debug XSS "$XSS"

  if [ -n "$XSS" ]; then
    _info "Authentication successful"
  else
    _err "Authentication failed"
    return 1
  fi

  BASE_URL=$(dirname $LOGIN_URL)
  CONF_ARGS="-ksSo /dev/null -b $COOKIE_JAR -c $COOKIE_JAR"
  UPLOAD="$CONF_ARGS $BASE_URL/_upload.jsp?request_type=xhr"
  CMD="$CONF_ARGS $BASE_URL/_cmdstat.jsp"

  REPLACE_CERT_AJAX='<ajax-request action="docmd" comp="system" updater="rid.0.5" xcmd="replace-cert" checkAbility="6" timeout="-1"><xcmd cmd="replace-cert" cn="'$RUCKUS_HOST'"/></ajax-request>'
  CERT_REBOOT_AJAX='<ajax-request action="docmd" comp="worker" updater="rid.0.5" xcmd="cert-reboot" checkAbility="6"><xcmd cmd="cert-reboot" action="undefined"/></ajax-request>'

  _info "Uploading certificate"
  curl $UPLOAD -H "X-CSRF-Token: $XSS" -F "u=@$_ccert" -F action=uploadcert -F callback=uploader_uploadcert || return 1

  _info "Uploading private key"
  curl $UPLOAD -H "X-CSRF-Token: $XSS" -F "u=@$_ckey" -F action=uploadprivatekey -F callback=uploader_uploadprivatekey || return 1

  _info "Replacing certificate"
  curl $CMD -H "X-CSRF-Token: $XSS" --data-raw "$REPLACE_CERT_AJAX" || return 1

  _info "Rebooting"
  curl $CMD -H "X-CSRF-Token: $XSS" --data-raw "$CERT_REBOOT_AJAX" || return 1

  return 0
}

