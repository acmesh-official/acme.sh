#!/usr/bin/env sh
#
# mikrotik.sh
# ===========
#
# Deploy certificate to a Mikrotik RouterOS system using the SSH protocol.
#
# The script must be able to connect to the remote host without a password.
# Therefore only public key authentication method is available and SSH keys must
# have been exchanged prior to running this script.
#
#
# Variables
# ---------
#
# The following variables can be exported in order to configure the script's
# behavior. When not set, values previously saved in _domain.conf_ are taken.
#
#
# DEPLOY_MIKROTIK_SET_API
# :    Deploy certificate also to the API-SSL service.
#
# DEPLOY_MIKROTIK_SSH_HOST
# :    Hostname or IP address to connect to the remote host. When not provided
#      use the domain name from the `acme.sh` command.
#
# DEPLOY_MIKROTIK_SSH_IDFILE
# :    Selects a file from which the identity (private key) for public key
#      authentication is read. When not provided, `ssh` default is used.
#
# DEPLOY_MIKROTIK_SSH_OPTIONS
# :    Additional options to pass to the `ssh` process.
#
# DEPLOY_MIKROTIK_SSH_PORT
# :    Port to connect to on the remote host.
#
# DEPLOY_MIKROTIK_SSH_USER
# :    Specifies the user to log in as on the remote machine. When not provide
#      use the current user name.
#
mikrotik_deploy() {
  _cdomain="${1}"
  _ckey="${2}"
  _ccert="${3}"
  _cca="${4}"
  _cfullchain="${5}"

  _debug _cdomain "${_cdomain}"
  _debug _ckey "${_ckey}"
  _debug _ccert "${_ccert}"
  _debug _cca "${_cca}"
  _debug _cfullchain "${_cfullchain}"

  _ssh_opts="${DEPLOY_MIKROTIK_SSH_OPTIONS}"
  if [ "${_ssh_opts}" ]; then
    _savedomainconf DEPLOY_MIKROTIK_SSH_OPTIONS "${_ssh_opts}"
  fi

  _ssh_host="${DEPLOY_MIKROTIK_SSH_HOST}"
  if [ "${_ssh_host}" ]; then
    _savedomainconf DEPLOY_MIKROTIK_SSH_HOST "${_ssh_host}"
  else
    _ssh_host="${_cdomain}"
  fi

  if [ "${DEPLOY_MIKROTIK_SET_API}" = "yes" ]; then
    _debug DEPLOY_MIKROTIK_SET_API "${DEPLOY_MIKROTIK_SET_API}"
    _savedomainconf DEPLOY_MIKROTIK_SET_API "${DEPLOY_MIKROTIK_SET_API}"
  fi

  if [ "${DEPLOY_MIKROTIK_SSH_IDFILE}" ]; then
    _debug DEPLOY_MIKROTIK_SSH_IDFILE "${DEPLOY_MIKROTIK_SSH_IDFILE}"

    _ssh_opts="${_ssh_opts} -i ${DEPLOY_MIKROTIK_SSH_IDFILE}"
    _savedomainconf DEPLOY_MIKROTIK_SSH_IDFILE "${DEPLOY_MIKROTIK_SSH_IDFILE}"
  fi

  if [ "${DEPLOY_MIKROTIK_SSH_PORT}" ]; then
    _debug DEPLOY_MIKROTIK_SSH_PORT "${DEPLOY_MIKROTIK_SSH_PORT}"

    _ssh_opts="${_ssh_opts} -p ${DEPLOY_MIKROTIK_SSH_PORT}"
    _savedomainconf DEPLOY_MIKROTIK_SSH_PORT "${DEPLOY_MIKROTIK_SSH_PORT}"
  fi

  if [ "${DEPLOY_MIKROTIK_SSH_USER}" ]; then
    _debug DEPLOY_MIKROTIK_SSH_USER "${DEPLOY_MIKROTIK_SSH_USER}"

    _ssh_host="${DEPLOY_MIKROTIK_SSH_USER}@${_ssh_host}"
    _savedomainconf DEPLOY_MIKROTIK_SSH_USER "${DEPLOY_MIKROTIK_SSH_USER}"
  fi

  _scp_opts=$(echo "${_ssh_opts} -q" | sed "s/-p/-P/g")
  _debug _ssh_host "${_ssh_host}"
  _debug _ssh_opts "${_ssh_opts}"
  _debug _scp_opts "${_scp_opts}"

  _ssh="ssh ${_ssh_opts} ${_ssh_host}"
  _scp="scp ${_scp_opts}"

  _debug _ssh "${_ssh}"
  _debug _scp "${_scp}"

  ${_ssh} /system resource print
  _ret=${?}
  if [ ${_ret} != "0" ]; then
    _err "Could not connect to ${_ssh_host}."
    return ${_ret}
  fi
  _info "Connected successfully to ${_ssh_host}."

  _info "Cleaning out old certificate from ${_ssh_host}."
  ${_ssh} /certificate remove [find name="${_cdomain}.pem_0"]
  ${_ssh} /file remove "${_cdomain}.pem"
  ${_ssh} /file remove "${_cdomain}.key"

  _info "Uploading certificate for ${_cdomain} to ${_ssh_host}."
  ${_scp} "${_cfullchain}" "${_ssh_host}:${_cdomain}.pem"
  ${_scp} "${_ckey}" "${_ssh_host}:${_cdomain}.key"

  _info "Setting up new certificate."
  ${_ssh} /certificate import file-name="${_cdomain}.pem" passphrase=\"\"
  ${_ssh} /certificate import file-name="${_cdomain}.key" passphrase=\"\"
  ${_ssh} /file remove "${_cdomain}.pem"
  ${_ssh} /file remove "${_cdomain}.key"

  ${_ssh} /ip service set www-ssl certificate="${_cdomain}.pem_0"
  if [ "${DEPLOY_MIKROTIK_SET_API}" = "yes" ]; then
    ${_ssh} /ip service set api-ssl certificate="${_cdomain}.pem_0"
  fi
}
