#!/usr/bin/env sh

#Here is a script to deploy cert to lighttpd server.

#returns 0 means success, otherwise error.

#DEPLOY_LIGHTTTPD_CONF="/etc/lighttpd/lighttpd.conf"
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
  _real_ca="$_ssl_path/lighttpd.ca.pem"
  if ! cat "$_cca" >"$_real_ca"; then
    _err "Error: write ca file to: $_real_ca"
    return 1
  fi
  _real_combinedkeyandcert="$_ssl_path/lighttpd.combined.pem"
  if ! cat "$_ckey" "$_ccert" >"$_real_combinedkeyandcert"; then
    _err "Error: write key file to: $_real_combinedkeyandcert"
    return 1
  fi

  DEFAULT_LIGHTTTPD_RELOAD="service lighttpd restart"
  _reload="${DEPLOY_LIGHTTTPD_RELOAD:-$DEFAULT_LIGHTTTPD_RELOAD}"

  if [ -z "$IS_RENEW" ]; then
    DEFAULT_LIGHTTTPD_CONF="/etc/lighttpd/lighttpd.conf"
    _LIGHTTTPD_conf="${DEPLOY_LIGHTTTPD_CONF:-$DEFAULT_LIGHTTTPD_CONF}"
    if [ ! -f "$_LIGHTTTPD_conf" ]; then
      if [ -z "$DEPLOY_LIGHTTTPD_CONF" ]; then
        _err "lighttpd conf is not found, please define DEPLOY_LIGHTTTPD_CONF"
        return 1
      else
        _err "It seems that the specified lighttpd conf is not valid, please check."
        return 1
      fi
    fi
    if [ ! -w "$_LIGHTTTPD_conf" ]; then
      _err "The file $_LIGHTTTPD_conf is not writable, please change the permission."
      return 1
    fi
    _backup_conf="$DOMAIN_BACKUP_PATH/lighttpd.conf.bak"
    _info "Backup $_LIGHTTTPD_conf to $_backup_conf"
      if ! mkdir -p "$DOMAIN_BACKUP_PATH"; then
        _err "Can not create folder:$DOMAIN_BACKUP_PATH"
      return 1
    fi
    if ! cat "$_LIGHTTTPD_conf" >"$_backup_conf"; then
      _err "Can not backup Lighttpd config to $_backup_conf"
      return 1
    fi

#    _info "Modify lighttpd conf: $_LIGHTTTPD_conf"
#    if _setopt "$_LIGHTTTPD_conf" "ssl.pemfile" "=" "$_real_combinedkeyandcert" \
#      && _setopt "$_LIGHTTTPD_conf" "ssl.ca-file" "=" "$_real_ca" \
#      && _setopt "$_LIGHTTTPD_conf" "ssl.engine" "=" "YES"; then
#      _info "Set config success!"
#    else
#      _err "Config lighttpd server error, please report bug to us."
#      _info "Restoring lighttpd conf"
#      if cat "$_backup_conf" >"$_LIGHTTTPD_conf"; then
#        _info "Restore conf success"
#        eval "$_reload"
#      else
#        _err "Oops, error restore lighttpd conf, please report bug to us."
#      fi
#      return 1
#    fi
  fi

  _info "Run reload: $_reload"
  if eval "$_reload"; then
    _info "Reload success!"
    if [ "$DEPLOY_LIGHTTTPD_CONF" ]; then
      _savedomainconf DEPLOY_LIGHTTTPD_CONF "$DEPLOY_LIGHTTTPD_CONF"
    else
      _cleardomainconf DEPLOY_LIGHTTTPD_CONF
    fi
    if [ "$DEPLOY_LIGHTTTPD_RELOAD" ]; then
      _savedomainconf DEPLOY_LIGHTTTPD_RELOAD "$DEPLOY_LIGHTTTPD_RELOAD"
    else
      _cleardomainconf DEPLOY_LIGHTTTPD_RELOAD
    fi
    return 0
  else
    _err "Reload error, restoring"
    if cat "$_backup_conf" >"$_LIGHTTTPD_conf"; then
      _info "Restore conf success"
      eval "$_reload"
    else
      _err "Oops, error restore lighttpd conf, please report bug to us."
    fi
    return 1
  fi
  return 0

}