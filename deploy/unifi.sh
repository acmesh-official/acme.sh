#!/usr/bin/env sh

#Here is a script to deploy cert to unifi server.

#returns 0 means success, otherwise error.

# Settings for Unifi Controller:
#DEPLOY_UNIFI_KEYSTORE="/usr/lib/unifi/data/keystore"
#DEPLOY_UNIFI_KEYPASS="aircontrolenterprise"
#DEPLOY_UNIFI_RELOAD="service unifi restart"

# Additional settings for Unifi Cloud Key:
#DEPLOY_UNIFI_CLOUDKEY=yes
#DEPLOY_UNIFI_CLOUDKEY_CERTDIR="/etc/ssl/private"
#DEPLOY_UNIFI_RELOAD="service unifi restart && service nginx restart"

########  Public functions #####################

#domain keyfile certfile cafile fullchain
unifi_deploy() {
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

  DEFAULT_DEPLOY_UNIFI_CLOUDKEY_CERTDIR="/etc/ssl/private"
  _cloudkey_certdir="${DEPLOY_UNIFI_CLOUDKEY_CERTDIR:-$DEFAULT_DEPLOY_UNIFI_CLOUDKEY_CERTDIR}"
  DEFAULT_DEPLOY_UNIFI_CLOUDKEY="no"
  if [ -f "${_cloudkey_certdir}/cloudkey.key" ]; then
    DEFAULT_DEPLOY_UNIFI_CLOUDKEY="yes"
  fi
  _cloudkey_deploy="${DEPLOY_UNIFI_CLOUDKEY:-$DEFAULT_DEPLOY_UNIFI_CLOUDKEY}"

  DEFAULT_UNIFI_KEYSTORE="/usr/lib/unifi/data/keystore"
  _unifi_keystore="${DEPLOY_UNIFI_KEYSTORE:-$DEFAULT_UNIFI_KEYSTORE}"
  DEFAULT_UNIFI_KEYPASS="aircontrolenterprise"
  _unifi_keypass="${DEPLOY_UNIFI_KEYPASS:-$DEFAULT_UNIFI_KEYPASS}"
  DEFAULT_UNIFI_RELOAD="service unifi restart"
  if [ "$_cloudkey_deploy" = "yes" ]; then
    DEFAULT_UNIFI_RELOAD="service nginx restart && ${DEFAULT_UNIFI_RELOAD}"
  fi
  _reload="${DEPLOY_UNIFI_RELOAD:-$DEFAULT_UNIFI_RELOAD}"

  _debug _unifi_keystore "$_unifi_keystore"
  if [ ! -f "$_unifi_keystore" ]; then
    if [ -z "$DEPLOY_UNIFI_KEYSTORE" ]; then
      _err "unifi keystore is not found, please define DEPLOY_UNIFI_KEYSTORE"
      return 1
    else
      _err "It seems that the specified unifi keystore is not valid, please check."
      return 1
    fi
  fi
  if [ ! -w "$_unifi_keystore" ]; then
    _err "The file $_unifi_keystore is not writable, please change the permission."
    return 1
  fi

  _debug _cloudkey_deploy "$_cloudkey_deploy"
  _debug _cloudkey_certdir "$_cloudkey_certdir"
  if [ "$_cloudkey_deploy" = "yes" ]; then
    if [ ! -d "$_cloudkey_certdir" ]; then
      _err "The directory $_cloudkey_certdir is missing or invalid; please define DEPLOY_UNIFI_CLOUDKEY_CERTDIR"
      return 1
    fi
    if [ ! -w "$_cloudkey_certdir" ]; then
      _err "The directory $_cloudkey_certdir is not writable; please check permissions"
      return 1
    fi
  fi

  _info "Generate import pkcs12"
  _import_pkcs12="$(_mktemp)"
  _toPkcs "$_import_pkcs12" "$_ckey" "$_ccert" "$_cca" "$_unifi_keypass" unifi root
  if [ "$?" != "0" ]; then
    _err "Oops, error creating import pkcs12, please report bug to us."
    return 1
  fi

  _info "Modify unifi keystore: $_unifi_keystore"
  if keytool -importkeystore \
    -deststorepass "$_unifi_keypass" -destkeypass "$_unifi_keypass" -destkeystore "$_unifi_keystore" \
    -srckeystore "$_import_pkcs12" -srcstoretype PKCS12 -srcstorepass "$_unifi_keypass" \
    -alias unifi -noprompt; then
    _info "Import keystore success!"
    rm "$_import_pkcs12"
  else
    _err "Import unifi keystore error, please report bug to us."
    rm "$_import_pkcs12"
    return 1
  fi

  if [ "$_cloudkey_deploy" = "yes" ]; then
    _info "Install Cloud Key certificate: $_cloudkey_certdir"
    cp "$_cfullchain" "${_cloudkey_certdir}/cloudkey.crt"
    cp "$_ckey" "${_cloudkey_certdir}/cloudkey.key"
    (cd "$_cloudkey_certdir" && tar -cf cert.tar cloudkey.crt cloudkey.key unifi.keystore.jks)
    _info "Install Cloud Key certificate success!"
  fi

  _info "Run reload: $_reload"
  if eval "$_reload"; then
    _info "Reload success!"
  else
    _err "Reload error"
    return 1
  fi

  if [ "$DEPLOY_UNIFI_KEYSTORE" ]; then
    _savedomainconf DEPLOY_UNIFI_KEYSTORE "$DEPLOY_UNIFI_KEYSTORE"
  else
    _cleardomainconf DEPLOY_UNIFI_KEYSTORE
  fi
  if [ "$DEPLOY_UNIFI_KEYPASS" ]; then
    _savedomainconf DEPLOY_UNIFI_KEYPASS "$DEPLOY_UNIFI_KEYPASS"
  else
    _cleardomainconf DEPLOY_UNIFI_KEYPASS
  fi
  if [ "$DEPLOY_UNIFI_RELOAD" ]; then
    _savedomainconf DEPLOY_UNIFI_RELOAD "$DEPLOY_UNIFI_RELOAD"
  else
    _cleardomainconf DEPLOY_UNIFI_RELOAD
  fi
  if [ "$DEPLOY_UNIFI_CLOUDKEY" ]; then
    _savedomainconf DEPLOY_UNIFI_CLOUDKEY "$DEPLOY_UNIFI_CLOUDKEY"
  else
    _cleardomainconf DEPLOY_UNIFI_CLOUDKEY
  fi
  if [ "$DEPLOY_UNIFI_CLOUDKEY_CERTDIR" ]; then
    _savedomainconf DEPLOY_UNIFI_CLOUDKEY_CERTDIR "$DEPLOY_UNIFI_CLOUDKEY_CERTDIR"
  else
    _cleardomainconf DEPLOY_UNIFI_CLOUDKEY_CERTDIR
  fi

  return 0
}
