#!/usr/bin/env sh

http_scp_info='SCP HTTP-01 validation plugin
Site: github.com/acmesh-official/acme.sh/wiki/HTTP-API
Docs: github.com/acmesh-official/acme.sh/wiki/HTTP-API#http_scp
Options:
 HTTP_SCP_USER Username for SSH/SCP
 HTTP_SCP_HOST Remote host
 HTTP_SCP_PATH Remote webroot path
 HTTP_SCP_PORT SSH port (optional)
 HTTP_SCP_KEY SSH private key path (optional)
'

#Here we implement scp-based http validation

#Returns 0 means success, otherwise error.

########  Public functions #####################

#Usage: http_scp_deploy domain token keyauthorization
http_scp_deploy() {
  _cdomain="$1"
  _ctoken="$2"
  _ckey="$3"

  _debug _cdomain "$_cdomain"
  _debug _ctoken "$_ctoken"

  _getconfig
  if [ "$?" != "0" ]; then
    return 1
  fi

  _info "Deploying challenge file to remote server using SCP"
  _wellknown_path="$HTTP_SCP_PATH/.well-known/acme-challenge"

  # Create temporary file with token content
  _tempcontent="$(_mktemp)"
  if [ "$?" != "0" ]; then
    _err "Failed to create temporary file"
    return 1
  fi

  echo "$_ckey" > "$_tempcontent"

  # Prepare SSH options
  _scp_options=""
  if [ -n "$HTTP_SCP_KEY" ]; then
    _scp_options="$_scp_options -i $HTTP_SCP_KEY"
  fi

  if [ -n "$HTTP_SCP_PORT" ]; then
    _scp_options="$_scp_options -P $HTTP_SCP_PORT"
  fi
  _scp_options="$_scp_options -o StrictHostKeyChecking=no"

  # Create challenge directory if it doesn't exist
  _info "Creating challenge directory on remote server"
  # shellcheck disable=SC2029  # We intentionally want client-side expansion of _wellknown_path
  if ! ssh $HTTP_SCP_USER@$HTTP_SCP_HOST $_scp_options "mkdir -p ${_wellknown_path}"; then
    _err "Failed to create challenge directory on remote server"
    rm -f "$_tempcontent"
    return 1
  fi

  # Upload challenge file
  _info "Uploading challenge file"
  if ! scp $_scp_options "$_tempcontent" $HTTP_SCP_USER@$HTTP_SCP_HOST:"${_wellknown_path}/${_ctoken}"; then
    _err "Failed to upload challenge file"
    rm -f "$_tempcontent"
    return 1
  fi

  rm -f "$_tempcontent"
  return 0
}

#Usage: http_scp_rm domain token
http_scp_rm() {
  _cdomain="$1"
  _ctoken="$2"

  _debug _cdomain "$_cdomain"
  _debug _ctoken "$_ctoken"

  _getconfig
  if [ "$?" != "0" ]; then
    return 1
  fi

  _info "Removing challenge file from remote server"
  _wellknown_path="$HTTP_SCP_PATH/.well-known/acme-challenge"

  # Prepare SSH options
  _scp_options=""
  if [ -n "$HTTP_SCP_KEY" ]; then
    _scp_options="$_scp_options -i $HTTP_SCP_KEY"
  fi

  if [ -n "$HTTP_SCP_PORT" ]; then
    _scp_options="$_scp_options -p $HTTP_SCP_PORT"
  else
    _scp_options="$_scp_options -p 22"
  fi
  _scp_options="$_scp_options -o StrictHostKeyChecking=no"

  # Remove challenge file
  _info "Removing challenge file from remote server"
  # shellcheck disable=SC2029  # We intentionally want client-side expansion of _wellknown_path and _ctoken
  if ! ssh $HTTP_SCP_USER@$HTTP_SCP_HOST $_scp_options "rm -f ${_wellknown_path}/${_ctoken}"; then
    _err "Failed to remove challenge file from remote server"
    return 1
  fi

  return 0
}

_getconfig() {
  if [ -z "$HTTP_SCP_USER" ]; then
    _err "HTTP_SCP_USER is not defined"
    return 1
  fi

  if [ -z "$HTTP_SCP_HOST" ]; then
    _err "HTTP_SCP_HOST is not defined"
    return 1
  fi

  if [ -z "$HTTP_SCP_PATH" ]; then
    _err "HTTP_SCP_PATH is not defined"
    return 1
  fi

  return 0
}
