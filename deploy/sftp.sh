#!/usr/bin/env sh

# Script to deploy certificates to remote server by SFTP
# Note that SFTP must be able to login to remote host without a password...
# SSH Keys must have been exchanged with the remote host.  Validate and
# test that you can login to USER@SERVER from the host running acme.sh before
# using this script.
#
# The following variables exported from environment will be used.
# If not set then values previously saved in <domain>.conf file are used.
#
# Only a host is required.  All others are optional.
#
# export DEPLOY_SFTP_HOSTS="192.168.0.1:22 admin@ssh.server.somewhere localhost" # required, multiple hosts allowed
# export DEPLOY_SFTP_KEYFILE="/etc/stunnel/stunnel.pem" # defaults to ~/acme_sftp_deploy/<domain>/<domain>.key
# export DEPLOY_SFTP_CERTFILE="/etc/stunnel/stunnel.pem" ~/acme_sftp_deploy/<domain>/<domain>.cer
# export DEPLOY_SFTP_CAFILE="/etc/stunnel/uca.pem" ~/acme_sftp_deploy/<domain>/ca.cer
# export DEPLOY_SFTP_FULLCHAIN="" ~/acme_sftp_deploy/<domain>/fullchain.cer

########  Public functions #####################

#domain keyfile certfile cafile fullchain
sftp_deploy() {
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

  # HOSTS is required to login by sftp to remote host.
  _migratedeployconf Le_Deploy_sftp_hosts DEPLOY_SFTP_HOSTS
  _getdeployconf DEPLOY_SFTP_HOSTS
  _debug2 DEPLOY_SFTP_HOSTS "$DEPLOY_SFTP_HOSTS"
  if [ -z "$DEPLOY_SFTP_HOSTS" ]; then
    _err "DEPLOY_SFTP_HOSTS not defined."
    return 1
  fi
  _savedeployconf DEPLOY_SFTP_HOSTS "$DEPLOY_SFTP_HOSTS"

  # KEYFILE is optional.
  # If provided then private key will be copied to provided filename.
  _migratedeployconf Le_Deploy_sftp_keyfile DEPLOY_SFTP_KEYFILE
  _getdeployconf DEPLOY_SFTP_KEYFILE
  _debug2 DEPLOY_SFTP_KEYFILE "$DEPLOY_SFTP_KEYFILE"
  if [ -n "$DEPLOY_SFTP_KEYFILE" ]; then
    _savedeployconf DEPLOY_SFTP_KEYFILE "$DEPLOY_SFTP_KEYFILE"
  fi

  # CERTFILE is optional.
  # If provided then certificate will be copied or appended to provided filename.
  _migratedeployconf Le_Deploy_sftp_certfile DEPLOY_SFTP_CERTFILE
  _getdeployconf DEPLOY_SFTP_CERTFILE
  _debug2 DEPLOY_SFTP_CERTFILE "$DEPLOY_SFTP_CERTFILE"
  if [ -n "$DEPLOY_SFTP_CERTFILE" ]; then
    _savedeployconf DEPLOY_SFTP_CERTFILE "$DEPLOY_SFTP_CERTFILE"
  fi

  # CAFILE is optional.
  # If provided then CA intermediate certificate will be copied or appended to provided filename.
  _migratedeployconf Le_Deploy_sftp_cafile DEPLOY_SFTP_CAFILE
  _getdeployconf DEPLOY_SFTP_CAFILE
  _debug2 DEPLOY_SFTP_CAFILE "$DEPLOY_SFTP_CAFILE"
  if [ -n "$DEPLOY_SFTP_CAFILE" ]; then
    _savedeployconf DEPLOY_SFTP_CAFILE "$DEPLOY_SFTP_CAFILE"
  fi

  # FULLCHAIN is optional.
  # If provided then fullchain certificate will be copied or appended to provided filename.
  _migratedeployconf Le_Deploy_sftp_fullchain DEPLOY_SFTP_FULLCHAIN
  _getdeployconf DEPLOY_SFTP_FULLCHAIN
  _debug2 DEPLOY_SFTP_FULLCHAIN "$DEPLOY_SFTP_FULLCHAIN"
  if [ -n "$DEPLOY_SFTP_FULLCHAIN" ]; then
    _savedeployconf DEPLOY_SFTP_FULLCHAIN "$DEPLOY_SFTP_FULLCHAIN"
  fi

  # Remote key file location, default ~/acme_sftp_deploy/domain/domain.key
  _ckey_path=".acme_sftp_deploy/$_cdomain/$_cdomain.key"
  if [ -n "$DEPLOY_SFTP_KEYFILE" ]; then
    _ckey_path="$DEPLOY_SFTP_KEYFILE"
  fi
  _debug _ckey_path "$_ckey_path"

  # Remote cert file location, default ~/acme_sftp_deploy/domain/domain.cer
  _ccert_path=".acme_sftp_deploy/$_cdomain/$_cdomain.cer"
  if [ -n "$DEPLOY_SFTP_CERTFILE" ]; then
    _ccert_path="$DEPLOY_SFTP_CERTFILE"
  fi
  _debug _ccert_path "$_ccert_path"

  # Remote intermediate CA file location, default ~/acme_sftp_deploy/domain/ca.cer
  _cca_path=".acme_sftp_deploy/$_cdomain/ca.cer"
  if [ -n "$DEPLOY_SFTP_CAFILE" ]; then
    _cca_path="$DEPLOY_SFTP_CAFILE"
  fi
  _debug _cca_path "$_cca_path"

  # Remote key file location, default ~/acme_sftp_deploy/domain/fullchain.cer
  _cfullchain_path=".acme_sftp_deploy/$_cdomain/fullchain.cer"
  if [ -n "$DEPLOY_SFTP_FULLCHAIN" ]; then
    _cfullchain_path="$DEPLOY_SFTP_FULLCHAIN"
  fi
  _debug _cfullchain_path "$_cfullchain_path"

  # Remote host, required non-empty but already checked before
  _sftp_hosts=$DEPLOY_SFTP_HOSTS
  _debug _sftp_hosts "$_sftp_hosts"

  # Initialize return value at 0
  _error_code=0

  # Always loop at least once
  for _sftp_host in $_sftp_hosts ; do
    sftp "$_sftp_host"\
<<EOF
put $_ckey $_ckey_path
put $_ccert $_ccert_path
put $_cca $_cca_path
put $_cfullchain $_cfullchain_path
EOF
    _sftp_error="$?"

    # Print error code in case of error
    if [ "$_sftp_error" -ne 0 ]; then
      _err "Error code $_sftp_error returned from sftp at host $_sftp_host"
    fi

    # Update global return value
    _error_code=$((_error_code || _sftp_error))
  done

  # Return 1 if any upload failed
  return "$_error_code"
}