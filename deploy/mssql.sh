#!/bin/bash

#Here is a script to deploy cert to mssql server.

#returns 0 means success, otherwise error.

#DEPLOY_mssql_CONF="/var/opt/mssql/mssql.conf"
#DEPLOY_mssql_RELOAD="systemctl restart mssql-server.service"

########  Public functions #####################

#domain keyfile certfile cafile fullchain
mssql_deploy() {
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

  _ssl_path="/etc/acme.sh/mssql"
  if ! mkdir -p "$_ssl_path"; then
    _err "Can not create folder:$_ssl_path"
    return 1
  fi

  mkdir -p "$DOMAIN_BACKUP_PATH"

  _info "Copying key and cert"
  _real_key="$_ssl_path/mssql.key"
  if ! cat "$_ckey" >"$_real_key"; then
    _err "Error: write key file to: $_real_key"
    return 1
  fi
  _real_fullchain="$_ssl_path/mssql.chain.pem"
  if ! cat "$_cfullchain" >"$_real_fullchain"; then
    _err "Error: write key file to: $_real_fullchain"
    return 1
  fi

  DEFAULT_mssql_RELOAD="systemctl restart mssql-server.service"
  _reload="${DEPLOY_mssql_RELOAD:-$DEFAULT_mssql_RELOAD}"

  if [ -z "$IS_RENEW" ]; then
    DEFAULT_mssql_CONF="/var/opt/mssql/mssql.conf"
    _mssql_conf="${DEPLOY_mssql_CONF:-$DEFAULT_mssql_CONF}"
    if [ ! -f "$_mssql_conf" ]; then
      if [ -z "$DEPLOY_mssql_CONF" ]; then
        _err "mssql conf is not found, please define DEPLOY_mssql_CONF"
        return 1
      else
        _err "It seems that the specified mssql conf is not valid, please check."
        return 1
      fi
    fi
    if [ ! -w "$_mssql_conf" ]; then
      _err "The file $_mssql_conf is not writable, please change the permission."
      return 1
    fi
    _backup_conf="$DOMAIN_BACKUP_PATH/mssql.conf.bak"
    _info "Backup $_mssql_conf to $_backup_conf"
    cp "$_mssql_conf" "$_backup_conf"

    _info "Modify mssql conf: $_mssql_conf"
    if /opt/mssql/bin/mssql-conf set network.tlscert "$_real_fullchain" &&
      /opt/mssql/bin/mssql-conf set network.tlskey "$_real_key"; then
      _info "Set config success!"
    else
      _err "Config mssql server error, please report bug to us."
      _info "Restoring mssql conf"
      if cat "$_backup_conf" >"$_mssql_conf"; then
        _info "Restore conf success"
        eval "$_reload"
      else
        _err "Oops, error restore mssql conf, please report bug to us."
      fi
      return 1
    fi
  fi

  _info "Run reload: $_reload"
  if eval "$_reload"; then
    _info "Reload success!"
    if [ "$DEPLOY_mssql_CONF" ]; then
      _savedomainconf DEPLOY_mssql_CONF "$DEPLOY_mssql_CONF"
    else
      _cleardomainconf DEPLOY_mssql_CONF
    fi
    if [ "$DEPLOY_mssql_RELOAD" ]; then
      _savedomainconf DEPLOY_mssql_RELOAD "$DEPLOY_mssql_RELOAD"
    else
      _cleardomainconf DEPLOY_mssql_RELOAD
    fi
    return 0
  else
    _err "Reload error, restoring"
    if cat "$_backup_conf" >"$_mssql_conf"; then
      _info "Restore conf success"
      eval "$_reload"
    else
      _err "Oops, error restore mssql conf, please report bug to us."
    fi
    return 1
  fi
  return 0
}
