#!/bin/bash

#Here is a script to deploy cert as a PKCS #12 / PFX certificate

#returns 0 means success, otherwise error.

#DEPLOY_PKCS12_KEYFILE=""
#DEPLOY_PKCS12_KEYPASS=""
#DEPLOY_PKCS12_RELOAD=""

########  Public functions #####################

#domain keyfile certfile cafile fullchain
pkcs12_deploy() {
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

  DEFAULT_PKCS12_KEYFILE=""
  _pkcs12_keyfile="${DEPLOY_PKCS12_KEYFILE:-$DEFAULT_PKCS12_KEYFILE}"
  DEFAULT_PKCS12_KEYPASS=""
  _pkcs12_keypass="${DEPLOY_PKCS12_KEYPASS:-$DEFAULT_PKCS12_KEYPASS}"
  DEFAULT_PKCS12_RELOAD=""
  _pkcs12_reload="${DEPLOY_PKCS12_RELOAD:-$DEFAULT_PKCS12_RELOAD}"

  _debug _pkcs12_keyfile "$_pkcs12_keyfile"
  if [ -z "$_pkcs12_keyfile" ]; then
    _err "Missing argument where to deploy the certificate key, please set DEPLOY_PKCS12_KEYFILE."
    return 1
  elif [ -a "$_pkcs12_keyfile" ]; then
    if [ ! -f "$_pkcs12_keyfile" ]; then
      _err "The file $_pkcs12_keyfile is not a regular file, please check."
      return 1
    elif [ ! -w "$_pkcs12_keyfile" ]; then
      _err "The file $_pkcs12_keyfile is not writable, please change the permission."
      return 1
    fi
  fi
  if [ -z "$_pkcs12_keypass" ]; then
    _err "Missing argument specifiying the password for the certificate key, please set DEPLOY_PKCS12_KEYPASS."
    return 1
  fi

  _info "Generate pkcs12"
  _toPkcs "$_pkcs12_keyfile" "$_ckey" "$_ccert" "$_cca" "$_pkcs12_keypass"
  if [ "$?" != "0" ]; then
    _err "Oops, error creating pkcs12, please report bug to us."
    return 1
  fi

  if [ -n "$_pkcs12_reload" ]; then
    _info "Run reload: $_pkcs12_reload"
    if eval "$_pkcs12_reload"; then
      _info "Reload success!"
    else
      _err "Reload error"
      return 1
    fi
  fi

  if [ "$DEPLOY_PKCS12_KEYFILE" ]; then
    _savedomainconf DEPLOY_PKCS12_KEYFILE "$DEPLOY_PKCS12_KEYFILE"
  else
    _cleardomainconf DEPLOY_PKCS12_KEYFILE
  fi
  if [ "$DEPLOY_PKCS12_KEYPASS" ]; then
    _savedomainconf DEPLOY_PKCS12_KEYPASS "$DEPLOY_PKCS12_KEYPASS"
  else
    _cleardomainconf DEPLOY_PKCS12_KEYPASS
  fi
  if [ "$DEPLOY_PKCS12_RELOAD" ]; then
    _savedomainconf DEPLOY_PKCS12_RELOAD "$DEPLOY_PKCS12_RELOAD"
  else
    _cleardomainconf DEPLOY_PKCS12_RELOAD
  fi
  return 0

}
