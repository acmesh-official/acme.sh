#!/usr/bin/env sh

#Here is a script to deploy cert to webmin server.

#returns 0 means success, otherwise error.

#DEPLOY_WEBMIN_CONF="/etc/webmin/miniserv.conf"
#DEPLOY_WEBMIN_RELOAD="service webmin restart"

########  Public functions #####################

#domain keyfile certfile cafile fullchain
webmin_deploy() {
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

  _ssl_path="/etc/acme.sh/webmin"
  if ! mkdir -p "$_ssl_path"; then
    _err "Can not create folder:$_ssl_path"
    return 1
  fi

  _info "Copying key and cert"
  _real_key="$_ssl_path/webmin.key"
  if ! cat "$_ckey" >"$_real_key"; then
    _err "Error: write key file to: $_real_key"
    return 1
  fi
  
  _real_fullchain="$_ssl_path/webmin.pem"
  if ! cat "$_real_key" "$_cfullchain" > "$_real_fullchain"; then
    _err "Error: write key file to: $_real_fullchain"
    return 1
  fi

  DEFAULT_WEBMIN_RELOAD="service webmin restart"
  _reload="${DEPLOY_WEBMIN_RELOAD:-$DEFAULT_WEBMIN_RELOAD}"

  if [ -z "$IS_RENEW" ]; then
    DEFAULT_WEBMIN_CONF="/etc/webmin/miniserv.conf"
    _webmin_conf="${DEPLOY_WEBMIN_CONF:-$DEFAULT_WEBMIN_CONF}"
    if [ ! -f "$_webmin_conf" ]; then
      if [ -z "$DEPLOY_WEBMIN_CONF" ]; then
        _err "webmin conf is not found, please define DEPLOY_WEBMIN_CONF"
        return 1
      else
        _err "It seems that the specified webmin conf is not valid, please check."
        return 1
      fi
    fi
    if [ ! -w "$_webmin_conf" ]; then
      _err "The file $_webmin_conf is not writable, please change the permission."
      return 1
    fi
    _backup_conf="$DOMAIN_BACKUP_PATH/miniserv.conf.bak"
    _info "Backup $_webmin_conf to $_backup_conf"
    cp "$_webmin_conf" "$_backup_conf"

    _info "Modify webmin conf: $_webmin_conf"
    if _setopt "$_webmin_conf" "keyfile""=""$_real_fullchain" \
      && _setopt "$_webmin_conf" "extracas""=""$_ssl_path/ca.cer"; then
      _info "Set config success!"
    else
      _err "Config webmin server error, please report bug to us."
      _info "Restoring webmin conf"
      if cat "$_backup_conf" >"$_webmin_conf"; then
        _info "Restore conf success"
        eval "$_reload"
      else
        _err "Opps, error restore webmin conf, please report bug to us."
      fi
      return 1
    fi
  fi

  _info "Run reload: $_reload"
  if eval "$_reload"; then
    _info "Reload success!"
    if [ "$DEPLOY_WEBMIN_CONF" ]; then
      _savedomainconf DEPLOY_WEBMIN_CONF "$DEPLOY_WEBMIN_CONF"
    else
      _cleardomainconf DEPLOY_WEBMIN_CONF
    fi
    if [ "$DEPLOY_WEBMIN_RELOAD" ]; then
      _savedomainconf DEPLOY_WEBMIN_RELOAD "$DEPLOY_WEBMIN_RELOAD"
    else
      _cleardomainconf DEPLOY_WEBMIN_RELOAD
    fi
    return 0
  else
    _err "Reload error, restoring"
    if cat "$_backup_conf" >"$_webmin_conf"; then
      _info "Restore conf success"
      eval "$_reload"
    else
      _err "Opps, error restore webmin conf, please report bug to us."
    fi
    return 1
  fi
  return 0
}
