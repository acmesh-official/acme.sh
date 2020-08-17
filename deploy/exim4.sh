#!/usr/bin/env sh

#Here is a script to deploy cert to exim4 server.

#returns 0 means success, otherwise error.

#DEPLOY_EXIM4_CONF="/etc/exim/exim.conf"
#DEPLOY_EXIM4_RELOAD="service exim4 restart"

########  Public functions #####################

#domain keyfile certfile cafile fullchain
exim4_deploy() {
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

  _ssl_path="/etc/acme.sh/exim4"
  if ! mkdir -p "$_ssl_path"; then
    _err "Can not create folder:$_ssl_path"
    return 1
  fi

  _info "Copying key and cert"
  _real_key="$_ssl_path/exim4.key"
  if ! cat "$_ckey" >"$_real_key"; then
    _err "Error: write key file to: $_real_key"
    return 1
  fi
  _real_fullchain="$_ssl_path/exim4.pem"
  if ! cat "$_cfullchain" >"$_real_fullchain"; then
    _err "Error: write key file to: $_real_fullchain"
    return 1
  fi

  DEFAULT_EXIM4_RELOAD="service exim4 restart"
  _reload="${DEPLOY_EXIM4_RELOAD:-$DEFAULT_EXIM4_RELOAD}"

  if [ -z "$IS_RENEW" ]; then
    DEFAULT_EXIM4_CONF="/etc/exim/exim.conf"
    if [ ! -f "$DEFAULT_EXIM4_CONF" ]; then
      DEFAULT_EXIM4_CONF="/etc/exim4/exim4.conf.template"
    fi
    _exim4_conf="${DEPLOY_EXIM4_CONF:-$DEFAULT_EXIM4_CONF}"
    _debug _exim4_conf "$_exim4_conf"
    if [ ! -f "$_exim4_conf" ]; then
      if [ -z "$DEPLOY_EXIM4_CONF" ]; then
        _err "exim4 conf is not found, please define DEPLOY_EXIM4_CONF"
        return 1
      else
        _err "It seems that the specified exim4 conf is not valid, please check."
        return 1
      fi
    fi
    if [ ! -w "$_exim4_conf" ]; then
      _err "The file $_exim4_conf is not writable, please change the permission."
      return 1
    fi
    _backup_conf="$DOMAIN_BACKUP_PATH/exim4.conf.bak"
    _info "Backup $_exim4_conf to $_backup_conf"
    cp "$_exim4_conf" "$_backup_conf"

    _info "Modify exim4 conf: $_exim4_conf"
    if _setopt "$_exim4_conf" "tls_certificate" "=" "$_real_fullchain" &&
      _setopt "$_exim4_conf" "tls_privatekey" "=" "$_real_key"; then
      _info "Set config success!"
    else
      _err "Config exim4 server error, please report bug to us."
      _info "Restoring exim4 conf"
      if cat "$_backup_conf" >"$_exim4_conf"; then
        _info "Restore conf success"
        eval "$_reload"
      else
        _err "Oops, error restore exim4 conf, please report bug to us."
      fi
      return 1
    fi
  fi

  _info "Run reload: $_reload"
  if eval "$_reload"; then
    _info "Reload success!"
    if [ "$DEPLOY_EXIM4_CONF" ]; then
      _savedomainconf DEPLOY_EXIM4_CONF "$DEPLOY_EXIM4_CONF"
    else
      _cleardomainconf DEPLOY_EXIM4_CONF
    fi
    if [ "$DEPLOY_EXIM4_RELOAD" ]; then
      _savedomainconf DEPLOY_EXIM4_RELOAD "$DEPLOY_EXIM4_RELOAD"
    else
      _cleardomainconf DEPLOY_EXIM4_RELOAD
    fi
    return 0
  else
    _err "Reload error, restoring"
    if cat "$_backup_conf" >"$_exim4_conf"; then
      _info "Restore conf success"
      eval "$_reload"
    else
      _err "Oops, error restore exim4 conf, please report bug to us."
    fi
    return 1
  fi
  return 0

}
