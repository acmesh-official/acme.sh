#!/usr/bin/bash

#Here is a script to deploy cert to eset server appliance, using Tomcat
# https://www.eset.com/de/business/security-management-center/

#returns 0 means success, otherwise error.

#DEPLOY_ESET_KEYSTORE="/etc/tomcat/.keystore"
#DEPLOY_ESET_KEYPASS="password"
#DEPLOY_ESET_RELOAD="systemctl restart tomcat"
#DEPLOY_ESET_TOMCAT=/etc/tomcat/server.xml

########  Public functions #####################

#domain keyfile certfile cafile fullchain
eset_deploy() {
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

  DEFAULT_ESET_TOMCAT=/etc/tomcat/server.xml
  _eset_tomcat="${DEPLOY_ESET_TOMCAT:-$DEFAULT_ESET_TOMCAT}"

  PARSED_ESET_KEYSTORE=$(echo 'cat //Service[@name="Catalina"]/Connector/@keystoreFile' | xmllint --nowrap --shell "$_eset_tomcat" | awk -F'[="]' '!/>/{print $(NF-1)}')
  if [ -z "$PARSED_ESET_KEYSTORE" ]; then
    DEFAULT_ESET_KEYSTORE="/etc/tomcat/.keystore"
  else
    DEFAULT_ESET_KEYSTORE=$PARSED_ESET_KEYSTORE
  fi
  _eset_keystore="${DEPLOY_ESET_KEYSTORE:-$DEFAULT_ESET_KEYSTORE}"

  PARSED_ESET_KEYPASS=$(echo 'cat //Service[@name="Catalina"]/Connector/@keystorePass' | xmllint --nowrap --shell "$_eset_tomcat" | awk -F'[="]' '!/>/{print $(NF-1)}')
  if [ -z "$PARSED_ESET_KEYPASS" ]; then
    DEFAULT_ESET_KEYPASS="password"
  else
    DEFAULT_ESET_KEYPASS=$PARSED_ESET_KEYPASS
  fi
  _eset_keypass="${DEPLOY_ESET_KEYPASS:-$DEFAULT_ESET_KEYPASS}"

  PARSED_ESET_KEYALIAS=$(echo 'cat //Service[@name="Catalina"]/Connector/@keyAlias' | xmllint --nowrap --shell "$_eset_tomcat" | awk -F'[="]' '!/>/{print $(NF-1)}')
  if [ -z "$PARSED_ESET_KEYALIAS" ]; then
    DEFAULT_ESET_KEYALIAS="tomcat"
  else
    DEFAULT_ESET_KEYALIAS="$PARSED_ESET_KEYALIAS"
  fi
  _eset_keyalias="${DEPLOY_ESET_KEYALIAS:-$DEFAULT_ESET_KEYALIAS}"


  DEFAULT_ESET_RELOAD="systemctl restart tomcat"
  _reload="${DEPLOY_ESET_RELOAD:-$DEFAULT_ESET_RELOAD}"


  _debug _eset_tomcat "$_eset_tomcat"
  _debug _eset_keystore "$_eset_keystore"
  _debug _eset_keypass "$_eset_keypass"
  _debug _eset_keyalias "$_eset_keyalias"
  if [ ! -f "$_eset_keystore" ]; then
    if [ -z "$DEPLOY_ESET_KEYSTORE" ]; then
      _err "eset keystore is not found, please define DEPLOY_ESET_KEYSTORE"
      return 1
    else
      _err "It seems that the specified eset keystore is not valid, please check."
      return 1
    fi
  fi
  if [ ! -w "$_eset_keystore" ]; then
    _err "The file $_eset_keystore is not writable, please change the permission."
    return 1
  fi

  _import_pkcs12="$(_mktemp)"
  _info "Generate import pkcs12 $_import_pkcs12"
  _toPkcs "$_import_pkcs12" "$_ckey" "$_ccert" "$_cca" "$_eset_keypass" "$_eset_keyalias" root
  if [ "$?" != "0" ]; then
    _err "Oops, error creating import pkcs12, please report bug to us."
    return 1
  fi

  _info "Delete old eset cert in keystore: $_eset_keystore"
  if keytool \
    -storepass "$_eset_keypass" -keystore "$_eset_keystore" \
    -delete -alias "$_eset_keyalias" -noprompt; then
    _info "Delete old cert success!"
  else
    _err "Error deleting old eset cert from keystore error, please report bug to us."
    #return 1
  fi

  _info "Modify eset keystore: $_eset_keystore"
  if keytool -importkeystore \
    -deststorepass "$_eset_keypass" -destkeypass "$_eset_keypass" -destkeystore "$_eset_keystore" \
    -srckeystore "$_import_pkcs12" -srcstoretype PKCS12 -srcstorepass "$_eset_keypass" \
    -alias "$_eset_keyalias" -noprompt; then
    _info "Import keystore success!"
    rm "$_import_pkcs12"
  else
    _err "Import eset keystore error, please report bug to us."
    rm "$_import_pkcs12"
    return 1
  fi

  _info "Run reload: $_reload"
  if eval "$_reload"; then
    _info "Reload success!"
    if [ "$DEPLOY_ESET_KEYSTORE" ]; then
      _savedomainconf DEPLOY_ESET_KEYSTORE "$DEPLOY_ESET_KEYSTORE"
    else
      _cleardomainconf DEPLOY_ESET_KEYSTORE
    fi
    if [ "$DEPLOY_ESET_KEYPASS" ]; then
      _savedomainconf DEPLOY_ESET_KEYPASS "$DEPLOY_ESET_KEYPASS"
    else
      _cleardomainconf DEPLOY_ESET_KEYPASS
    fi
    if [ "$DEPLOY_ESET_RELOAD" ]; then
      _savedomainconf DEPLOY_ESET_RELOAD "$DEPLOY_ESET_RELOAD"
    else
      _cleardomainconf DEPLOY_ESET_RELOAD
    fi
    return 0
  else
    _err "Reload error"
    return 1
  fi
  return 0

}
