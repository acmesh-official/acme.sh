#!/usr/bin/env sh

#Here is a script to deploy cert to nghttpx server.

#returns 0 means success, otherwise error.

#DEPLOY_NGHTTPX_CONF="/etc/nghttpx/nghttpx.conf"
#DEPLOY_NGHTTPX_RELOAD="service nghttpx restart"

########  Public functions #####################

#domain keyfile certfile cafile fullchain
nghttpx_deploy() {
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

  _ssl_path="/etc/acme.sh/nghttpx"
  if ! mkdir -p "$_ssl_path"; then
    _err "Can not create folder:$_ssl_path"
    return 1
  fi

  _info "Copying key and cert"
  _real_key="$_ssl_path/$_cdomain.key"
  if ! cat "$_ckey" >"$_real_key"; then
    _err "Error: write key file to: $_real_key"
    return 1
  fi
  _real_fullchain="$_ssl_path/$_cdomain.chain.pem"
  if ! cat "$_cfullchain" >"$_real_fullchain"; then
    _err "Error: write key file to: $_real_fullchain"
    return 1
  fi

  DEFAULT_NGHTTPX_RELOAD="service nghttpx restart"
  _reload="${DEPLOY_NGHTTPX_RELOAD:-$DEFAULT_NGHTTPX_RELOAD}"

  if [ -z "$IS_RENEW" ]; then
    DEFAULT_NGHTTPX_CONF="/etc/nghttpx/nghttpx.conf"
    _nghttpx_conf="${DEPLOY_NGHTTPX_CONF:-$DEFAULT_NGHTTPX_CONF}"
    if [ ! -f "$_nghttpx_conf" ]; then
      if [ -z "$DEPLOY_NGHTTPX_CONF" ]; then
        _err "nghttpx conf is not found, please define DEPLOY_NGHTTPX_CONF"
        return 1
      else
        _err "It seems that the specified nghttpx conf is not valid, please check."
        return 1
      fi
    fi
    if [ ! -w "$_nghttpx_conf" ]; then
      _err "The file $_nghttpx_conf is not writable, please change the permission."
      return 1
    fi
    _backup_conf="$DOMAIN_BACKUP_PATH/nghttpx.conf.bak"
    _info "Backup $_nghttpx_conf to $_backup_conf"
    mkdir -p "$DOMAIN_BACKUP_PATH"
    cp "$_nghttpx_conf" "$_backup_conf"

    _info "Modify nghttpx conf: $_nghttpx_conf"
    if echo "subcert=$_real_key:$_real_fullchain" >> "$_nghttpx_conf"; then
      _info "Set config success!"
    else
      _err "Config nghttpx server error, please report bug to us."
      _info "Restoring nghttpx conf"
      if cat "$_backup_conf" >"$_nghttpx_conf"; then
        _info "Restore conf success"
        eval "$_reload"
      else
        _err "Oops, error restore nghttpx conf, please report bug to us."
      fi
      return 1
    fi
  fi

  _info "Run reload: $_reload"
  if eval "$_reload"; then
    _info "Reload success!"
    if [ "$DEPLOY_NGHTTPX_CONF" ]; then
      _savedomainconf DEPLOY_NGHTTPX_CONF "$DEPLOY_NGHTTPX_CONF"
    else
      _cleardomainconf DEPLOY_NGHTTPX_CONF
    fi
    if [ "$DEPLOY_NGHTTPX_RELOAD" ]; then
      _savedomainconf DEPLOY_NGHTTPX_RELOAD "$DEPLOY_NGHTTPX_RELOAD"
    else
      _cleardomainconf DEPLOY_NGHTTPX_RELOAD
    fi
    return 0
  else
    _err "Reload error, restoring"
    if cat "$_backup_conf" >"$_nghttpx_conf"; then
      _info "Restore conf success"
      eval "$_reload"
    else
      _err "Oops, error restore nghttpx conf, please report bug to us."
    fi
    return 1
  fi
  return 0
}
