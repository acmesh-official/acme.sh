#!/usr/bin/env sh

#Here is a script to deploy cert to vsftpd server.

#returns 0 means success, otherwise error.

#DEPLOY_VSFTPD_CONF="/etc/vsftpd.conf"
#DEPLOY_VSFTPD_RELOAD="service vsftpd restart"

########  Public functions #####################

#domain keyfile certfile cafile fullchain
vsftpd_deploy() {
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

  _ssl_path="/etc/acme.sh/vsftpd"
  if ! mkdir -p "$_ssl_path"; then
    _err "Can not create folder:$_ssl_path"
    return 1
  fi

  _info "Copying key and cert"
  _real_key="$_ssl_path/vsftpd.key"
  if ! cat "$_ckey" >"$_real_key"; then
    _err "Error: write key file to: $_real_key"
    return 1
  fi
  _real_fullchain="$_ssl_path/vsftpd.chain.pem"
  if ! cat "$_cfullchain" >"$_real_fullchain"; then
    _err "Error: write key file to: $_real_fullchain"
    return 1
  fi

  DEFAULT_VSFTPD_RELOAD="service vsftpd restart"
  _reload="${DEPLOY_VSFTPD_RELOAD:-$DEFAULT_VSFTPD_RELOAD}"

  if [ -z "$IS_RENEW" ]; then
    DEFAULT_VSFTPD_CONF="/etc/vsftpd.conf"
    _vsftpd_conf="${DEPLOY_VSFTPD_CONF:-$DEFAULT_VSFTPD_CONF}"
    if [ ! -f "$_vsftpd_conf" ]; then
      if [ -z "$DEPLOY_VSFTPD_CONF" ]; then
        _err "vsftpd conf is not found, please define DEPLOY_VSFTPD_CONF"
        return 1
      else
        _err "It seems that the specified vsftpd conf is not valid, please check."
        return 1
      fi
    fi
    if [ ! -w "$_vsftpd_conf" ]; then
      _err "The file $_vsftpd_conf is not writable, please change the permission."
      return 1
    fi
    _backup_conf="$DOMAIN_BACKUP_PATH/vsftpd.conf.bak"
    _info "Backup $_vsftpd_conf to $_backup_conf"
    cp "$_vsftpd_conf" "$_backup_conf"

    _info "Modify vsftpd conf: $_vsftpd_conf"
    if _setopt "$_vsftpd_conf" "rsa_cert_file" "=" "$_real_fullchain" &&
      _setopt "$_vsftpd_conf" "rsa_private_key_file" "=" "$_real_key" &&
      _setopt "$_vsftpd_conf" "ssl_enable" "=" "YES"; then
      _info "Set config success!"
    else
      _err "Config vsftpd server error, please report bug to us."
      _info "Restoring vsftpd conf"
      if cat "$_backup_conf" >"$_vsftpd_conf"; then
        _info "Restore conf success"
        eval "$_reload"
      else
        _err "Oops, error restore vsftpd conf, please report bug to us."
      fi
      return 1
    fi
  fi

  _info "Run reload: $_reload"
  if eval "$_reload"; then
    _info "Reload success!"
    if [ "$DEPLOY_VSFTPD_CONF" ]; then
      _savedomainconf DEPLOY_VSFTPD_CONF "$DEPLOY_VSFTPD_CONF"
    else
      _cleardomainconf DEPLOY_VSFTPD_CONF
    fi
    if [ "$DEPLOY_VSFTPD_RELOAD" ]; then
      _savedomainconf DEPLOY_VSFTPD_RELOAD "$DEPLOY_VSFTPD_RELOAD"
    else
      _cleardomainconf DEPLOY_VSFTPD_RELOAD
    fi
    return 0
  else
    _err "Reload error, restoring"
    if cat "$_backup_conf" >"$_vsftpd_conf"; then
      _info "Restore conf success"
      eval "$_reload"
    else
      _err "Oops, error restore vsftpd conf, please report bug to us."
    fi
    return 1
  fi
  return 0
}
