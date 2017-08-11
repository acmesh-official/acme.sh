#!/usr/bin/env sh

#Here is a script to deploy cert to lighttpd server.

#returns 0 means success, otherwise error.

#DEPLOY_LIGHTTTPD_RELOAD="service lighttpd restart"

########  Public functions #####################

#domain keyfile certfile cafile fullchain
lighttpd_deploy() {
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

  _ssl_path="/etc/acme.sh/lighttpd"
  if ! mkdir -p "$_ssl_path"; then
    _err "Can not create folder:$_ssl_path"
    return 1
  fi

  _info "Copying combined key and cert and CA chain"
  _real_ca="$_ssl_path/letsencrypt.ca.pem"
  if ! cat "$_cca" >"$_real_ca"; then
    _err "Error: write ca file to: $_real_ca"
    return 1
  fi
  _real_combinedkeyandcert="$_ssl_path/$_cdomain.pem"
  if ! cat "$_ckey" "$_ccert" >"$_real_combinedkeyandcert"; then
    _err "Error: write key file to: $_real_combinedkeyandcert"
    return 1
  fi

  DEFAULT_LIGHTTTPD_RELOAD="service lighttpd restart"
  _reload="${DEPLOY_LIGHTTTPD_RELOAD:-$DEFAULT_LIGHTTTPD_RELOAD}"

  _info "Run reload: $_reload"
  if eval "$_reload"; then
    _info "Reload success!"
    if [ "$DEPLOY_LIGHTTTPD_RELOAD" ]; then
      _savedomainconf DEPLOY_LIGHTTTPD_RELOAD "$DEPLOY_LIGHTTTPD_RELOAD"
    else
      _cleardomainconf DEPLOY_LIGHTTTPD_RELOAD
    fi
    return 0
  else
    return 1
  fi
  return 0
}
