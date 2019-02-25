#!/usr/bin/env sh

#Here is a script to deploy cert to postfix servers.

#returns 0 means success, otherwise error.

#DEFAULT_POSTFIX_RELOAD="service postfix restart"
#DEFAULT_POSTFIX_CONF="/etc/postfix/main.cf"


########  Public functions #####################

#domain keyfile certfile cafile fullchain
postfix_deploy() {
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

  _ssl_path="/etc/acme.sh/postfix"
  if ! mkdir -p "$_ssl_path"; then
    _err "Can not create folder:$_ssl_path"
    return 1
  fi

  _info "Copying key and cert"
  _real_key="$_ssl_path/postfix.key"
  if ! cat "$_ckey" >"$_real_key"; then
    _err "Error: write key file to: $_real_key"
    return 1
  fi
  _real_fullchain="$_ssl_path/postfix.chain.pem"
  if ! cat "$_cfullchain" >"$_real_fullchain"; then
    _err "Error: write key file to: $_real_fullchain"
    return 1
  fi

  DEFAULT_POSTFIX_RELOAD="service postfix restart"
  _reload_postfix="${DEPLOY_POSTFIX_RELOAD:-$DEFAULT_POSTFIX_RELOAD}"

  if [ -z "$IS_RENEW" ]; then
    DEFAULT_POSTFIX_CONF="/etc/postfix/main.cf"
    _postfix_conf="${DEPLOY_POSTFIX_CONF:-$DEFAULT_POSTFIX_CONF}"

    if [ ! -f "$_postfix_conf" ]; then
      if [ -z "$DEPLOY_POSTFIX_CONF" ]; then
        _err "postfix conf is not found, please define DEPLOY_POSTFIX_CONF"
        return 1
      else
        _err "It seems that the specified postfix conf is not valid, please check."
        return 1
      fi
    fi
    if [ ! -w "$_postfix_conf" ]; then
      _err "The file $_postfix_conf is not writable, please change the permission."
      return 1
    fi
    _backup_postfix_conf="$DOMAIN_BACKUP_PATH/postfix.conf.bak"
    _info "Backup $_postfix_conf to $_backup_postfix_conf"
    cp "$_postfix_conf" "$_backup_postfix_conf"

    _info "Modify postfix conf: $_postfix_conf"
    if _setopt "$_postfix_conf" "smtpd_tls_cert_file" "=" "$_real_fullchain" \
      && _setopt "$_postfix_conf" "smtpd_tls_key_file" "=" "$_real_key" \
      && _setopt "$_postfix_conf" "smtpd_use_tls" "=" "yes" \
      && _setopt "$_postfix_conf" "smtpd_tls_security_level" "=" "may"; then
      _info "Set config success!"
    else
      _err "Config postfix server error, please report bug to us."
      _info "Restoring postfix conf"
      if cat "$_backup_postfix_conf" >"$_postfix_conf"; then
        _info "Restore conf success"
        eval "$_reload_postfix"
      else
        _err "Oops, error restore postfix conf, please report bug to us."
      fi
      return 1
    fi
  fi

  _info "Run reload: $_reload_postfix"
  if eval "$_reload_postfix"; then
    _info "Reload success!"
    if [ "$DEPLOY_POSTFIX_CONF" ]; then
      _savedomainconf DEPLOY_POSTFIX_CONF "$DEPLOY_POSTFIX_CONF"
    else
      _cleardomainconf DEPLOY_POSTFIX_CONF
    fi
    if [ "$DEPLOY_POSTFIX_RELOAD" ]; then
      _savedomainconf DEPLOY_POSTFIX_RELOAD "$DEPLOY_POSTFIX_RELOAD"
    else
      _cleardomainconf DEPLOY_POSTFIX_RELOAD
    fi
    return 0
  else
    _err "Reload error, restoring conf"
    if cat "$_backup_postfix_conf" >"$_postfix_conf"; then
      _info "Restore postfox conf success"
      eval "$_reload_postfix"
    else
      _err "Oops, error restoring postfix conf, please report bug to us."
    fi
    return 1
  fi
  return 0
}
