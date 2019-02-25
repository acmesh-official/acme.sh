#!/usr/bin/env sh

#Here is a script to deploy cert to dovecot servers.

#returns 0 means success, otherwise error.

#DEFAULT_DOVECOT_RELOAD="service dovecot restart"
#DEFAULT_DOVECOT_CONF="/etc/dovecot/dovecot.conf"

########  Public functions #####################

#domain keyfile certfile cafile fullchain
dovecot_deploy() {
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

  _ssl_path="/etc/acme.sh/dovecot"
  if ! mkdir -p "$_ssl_path"; then
    _err "Can not create folder:$_ssl_path"
    return 1
  fi

  _info "Copying key and cert"
  _real_key="$_ssl_path/dovecot.key"
  if ! cat "$_ckey" >"$_real_key"; then
    _err "Error: write key file to: $_real_key"
    return 1
  fi
  _real_fullchain="$_ssl_path/dovecot.chain.pem"
  if ! cat "$_cfullchain" >"$_real_fullchain"; then
    _err "Error: write key file to: $_real_fullchain"
    return 1
  fi

  DEFAULT_DOVECOT_RELOAD="service dovecot restart"
  _reload_dovecot="${DEPLOY_DOVECOT_RELOAD:-$DEFAULT_DOVECOT_RELOAD}"

  if [ -z "$IS_RENEW" ]; then
    DEFAULT_DOVECOT_CONF="/etc/dovecot/dovecot.conf"
    _dovecot_conf="${DEPLOY_DOVECOT_CONF:-$DEFAULT_DOVECOT_CONF}"

    if [ ! -f "$_dovecot_conf" ]; then
      if [ -z "$DEPLOY_DOVECOT_CONF" ]; then
        _err "dovecot conf is not found, please define DEPLOY_DOVECOT_CONF"
        return 1
      else
        _err "It seems that the specified dovecot conf is not valid, please check."
        return 1
      fi
    fi
    if [ ! -w "$_dovecot_conf" ]; then
      _err "The file $_dovecot_conf is not writable, please change the permission."
      return 1
    fi
    _backup_dovecot_conf="$DOMAIN_BACKUP_PATH/dovecot.conf.bak"
    _info "Backup $_dovecot_conf to $_backup_dovecot_conf"
    cp "$_dovecot_conf" "$_backup_dovecot_conf"

    # dovecot needs the input redirectors ("<") before the filenames here
    _info "Modify dovecot conf: $_dovecot_conf"
    if _setopt "$_dovecot_conf" "ssl_cert" "=" "<$_real_fullchain" \
      && _setopt "$_dovecot_conf" "ssl_key" "=" "<$_real_key" \
      && _setopt "$_dovecot_conf" "ssl" "=" "required"; then
      _info "Set config success!"
    else
      _err "Config dovecot server error, please report bug to us."
      _info "Restoring dovecot conf"
      if cat "$_backup_dovecot_conf" >"$_dovecot_conf"; then
        _info "Restore conf success"
        eval "$_reload_dovecot"
      else
        _err "Oops, error restore dovecot conf, please report bug to us."
      fi
      return 1
    fi
  fi

  _info "Run reload: $_reload_dovecot"
  if eval "$_reload_dovecot"; then
    _info "Reload success!"
    if [ "$DEPLOY_DOVECOT_CONF" ]; then
      _savedomainconf DEPLOY_DOVECOT_CONF "$DEPLOY_DOVECOT_CONF"
    else
      _cleardomainconf DEPLOY_DOVECOT_CONF
    fi
    if [ "$DEPLOY_DOVECOT_RELOAD" ]; then
      _savedomainconf DEPLOY_DOVECOT_RELOAD "$DEPLOY_DOVECOT_RELOAD"
    else
      _cleardomainconf DEPLOY_DOVECOT_RELOAD
    fi
    return 0
  else
    _err "Reload error, restoring conf"
    if cat "$_backup_dovecot_conf" >"$_dovecot_conf"; then
      _info "Restore dovecot conf success"
      eval "$_reload_dovecot"
    else
      _err "Oops, error restoring dovecot conf, please report bug to us."
    fi
    return 1
  fi
  return 0
}
