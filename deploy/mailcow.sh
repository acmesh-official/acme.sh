#!/usr/bin/env sh

#Here is a script to deploy cert to mailcow.

#returns 0 means success, otherwise error.

########  Public functions #####################

#domain keyfile certfile cafile fullchain
mailcow_deploy() {
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

  _mailcow_path="${DEPLOY_MAILCOW_PATH}"

  if [ -z "$_mailcow_path" ]; then
    _err "Mailcow path is not found, please define DEPLOY_MAILCOW_PATH."
    return 1
  fi

  #Tests if _ssl_path is the mailcow root directory.
  if [ -f "${_mailcow_path}/generate_config.sh" ]; then
    _ssl_path="${_mailcow_path}/data/assets/ssl/"
  else
    _ssl_path="${_mailcow_path}"
  fi

  if [ ! -d "$_ssl_path" ]; then
    _err "Cannot find mailcow ssl path: $_ssl_path"
    return 1
  fi

  # ECC or RSA
  if [ -z "${Le_Keylength}" ]; then
    Le_Keylength=""
  fi
  if _isEccKey "${Le_Keylength}"; then
    _info "ECC key type detected"
    _cert_name_prefix="ecdsa-"
  else
    _info "RSA key type detected"
    _cert_name_prefix=""
  fi
  _info "Copying key and cert"
  _real_key="$_ssl_path/${_cert_name_prefix}key.pem"
  if ! cat "$_ckey" >"$_real_key"; then
    _err "Error: write key file to: $_real_key"
    return 1
  fi

  _real_fullchain="$_ssl_path/${_cert_name_prefix}cert.pem"
  if ! cat "$_cfullchain" >"$_real_fullchain"; then
    _err "Error: write cert file to: $_real_fullchain"
    return 1
  fi

  DEFAULT_MAILCOW_RELOAD="docker restart $(docker ps -qaf name=postfix-mailcow); docker restart $(docker ps -qaf name=nginx-mailcow); docker restart $(docker ps -qaf name=dovecot-mailcow)"
  _reload="${DEPLOY_MAILCOW_RELOAD:-$DEFAULT_MAILCOW_RELOAD}"

  _info "Run reload: $_reload"
  if eval "$_reload"; then
    _info "Reload success!"
  fi
  return 0

}
