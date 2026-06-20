#!/bin/bash

#Here is a script to deploy cert to tomcat8 server.

#returns 0 means success, otherwise error.

#DEPLOY_TOMCAT8_KEYSTORE="/usr/share/tomcat8/.keystore"
# should probably be /var/lib/tomcat8/keystore
#DEPLOY_TOMCAT8_KEYPASS="aircontrolenterprise"
#DEPLOY_TOMCAT8_RELOAD="service tomcat8 restart"

########  Public functions #####################

#domain keyfile certfile cafile fullchain
tomcat8_deploy() {
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

  if ! _exists keytool; then
    _err "keytool not found"
    return 1
  fi

  DEFAULT_TOMCAT8_KEYSTORE="/usr/share/tomcat8/.keystore"
  _tomcat8_keystore="${DEPLOY_TOMCAT8_KEYSTORE:-$DEFAULT_TOMCAT8_KEYSTORE}"
  DEFAULT_TOMCAT8_KEYPASS="aircontrolenterprise"
  _tomcat8_keypass="${DEPLOY_TOMCAT8_KEYPASS:-$DEFAULT_TOMCAT8_KEYPASS}"
  DEFAULT_TOMCAT8_RELOAD="service tomcat8 restart"
  _reload="${DEPLOY_TOMCAT8_RELOAD:-$DEFAULT_TOMCAT8_RELOAD}"

  _debug _tomcat8_keystore "$_tomcat8_keystore"
  if [ ! -f "$_tomcat8_keystore" ]; then
    if [ -z "$DEPLOY_TOMCAT8_KEYSTORE" ]; then
      _err "tomcat8 keystore is not found, please define DEPLOY_TOMCAT8_KEYSTORE"
      return 1
    else
      _err "It seems that the specified tomcat8 keystore is not valid, please check."
      return 1
    fi
  fi
  if [ ! -w "$_tomcat8_keystore" ]; then
    _err "The file $_tomcat8_keystore is not writable, please change the permission."
    return 1
  fi

  _info "Generate import pkcs12"
  _import_pkcs12="$(_mktemp)"
  _toPkcs "$_import_pkcs12" "$_ckey" "$_ccert" "$_cca" "$_tomcat8_keypass" tomcat8 root
  if [ "$?" != "0" ]; then
    _err "Oops, error creating import pkcs12, please report bug to us."
    return 1
  fi

  _info "Modify tomcat8 keystore: $_tomcat8_keystore"
  if keytool -importkeystore \
    -deststorepass "$_tomcat8_keypass" -destkeypass "$_tomcat8_keypass" -destkeystore "$_tomcat8_keystore" \
    -srckeystore "$_import_pkcs12" -srcstoretype PKCS12 -srcstorepass "$_tomcat8_keypass" \
    -alias tomcat8 -noprompt; then
    _info "Import keystore success!"
    rm "$_import_pkcs12"
  else
    _err "Import tomcat8 keystore error, please report bug to us."
    rm "$_import_pkcs12"
    return 1
  fi

  _info "Run reload: $_reload"
  if eval "$_reload"; then
    _info "Reload success!"
    if [ "$DEPLOY_TOMCAT8_KEYSTORE" ]; then
      _savedomainconf DEPLOY_TOMCAT8_KEYSTORE "$DEPLOY_TOMCAT8_KEYSTORE"
    else
      _cleardomainconf DEPLOY_TOMCAT8_KEYSTORE
    fi
    if [ "$DEPLOY_TOMCAT8_KEYPASS" ]; then
      _savedomainconf DEPLOY_TOMCAT8_KEYPASS "$DEPLOY_TOMCAT8_KEYPASS"
    else
      _cleardomainconf DEPLOY_TOMCAT8_KEYPASS
    fi
    if [ "$DEPLOY_TOMCAT8_RELOAD" ]; then
      _savedomainconf DEPLOY_TOMCAT8_RELOAD "$DEPLOY_TOMCAT8_RELOAD"
    else
      _cleardomainconf DEPLOY_TOMCAT8_RELOAD
    fi
    return 0
  else
    _err "Reload error"
    return 1
  fi
  return 0

}
