#!/usr/bin/env sh
#
#    Deploy cert to localhost similar to certbot behavior
#
#    export DEPLOY_LOCALHOST_ROOT_PATH="/path/to/certs"
#
#    Deploys as:
#        /path/to/certs/domain.tld/privkey.pem
#        /path/to/certs/domain.tld/cert.pem
#        /path/to/certs/domain.tld/ca.pem
#        /path/to/certs/domain.tld/fullchain.pem
#
#    $1=domain $2=keyfile $3=certfile $4=cafile $5=fullchain
#
localhost_deploy() {
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

  _getdeployconf DEPLOY_LOCALHOST_ROOT_PATH

  _debug DEPLOY_LOCALHOST_ROOT_PATH "$DEPLOY_LOCALHOST_ROOT_PATH"

  if [ -z "$_cdomain" ]; then
    _err "Domain not defined"
    return 1
  fi

  if [ -z "$DEPLOY_LOCALHOST_ROOT_PATH" ]; then
    _err "DEPLOY_LOCALHOST_ROOT_PATH not defined"
    return 1
  fi

  _ssl_path="$DEPLOY_LOCALHOST_ROOT_PATH"
  if [ ! -d "$_ssl_path" ]; then
    _err "Path not found: $_ssl_path"
    return 1
  fi

  _savedeployconf DEPLOY_LOCALHOST_ROOT_PATH "$DEPLOY_LOCALHOST_ROOT_PATH"

  _ssl_path="$_ssl_path/$_cdomain"
  mkdir -p "$_ssl_path"

  # ECC or RSA
  length=$(_readdomainconf Le_Keylength)
  if _isEccKey "$length"; then
    _info "ECC key type detected"
    _file_prefix="ecdsa-"
  else
    _info "RSA key type detected"
    _file_prefix=""
  fi

  _info "Copying cert files..."

  # {$2} _ckey
  _filename="$_ssl_path/${_file_prefix}privkey.pem"
  if ! cat "$_ckey" > "$_filename"; then
    err "Error: Can't write $_filename"
    return 1
  fi

  if ! chmod 600 "$_filename"; then
    err "Error: Can't set protected 600 permission on privkey.pem"
    rm -f "$_filename"
    return 1
  fi

  # {$3} _ccert
  _filename="$_ssl_path/${_file_prefix}cert.pem"
  if ! cat "$_ccert" > "$_filename"; then
    err "Error: Can't write $_filename"
    return 1
  fi

  # {$4} _cca
  _filename="$_ssl_path/${_file_prefix}ca.pem"
  if ! cat "$_cca" > "$_filename"; then
    err "Error: Can't write $_filename"
    return 1
  fi

  # {$5} _cfullchain
  _filename="$_ssl_path/${_file_prefix}fullchain.pem"
  if ! cat "$_cfullchain" > "$_filename"; then
    err "Error: Can't write $_filename"
    return 1
  fi

  _info "Done: Cert files copied to $_ssl_path/"

  return 0

}
