#!/usr/bin/env sh

# Script for acme.sh to deploy certificates to a VMware UAG appliance
#
# The following variables can be exported:
#
# export DEPLOY_VMWAREUAG_USERNAME="admin"
# export DEPLOY_VMWAREUAG_PASSWORD=""       # required
# export DEPLOY_VMWAREUAG_HOST=""           # required (comma seperated list)
# export DEPLOY_VMWAREUAG_PORT="9443"
# export DEPLOY_VMWAREUAG_SSL_VERIFY="yes"
#
#

########  Public functions #####################

#domain keyfile certfile cafile fullchain
vmwareuag_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"

  # Some defaults
  DEPLOY_VMWAREUAG_USERNAME_DEFAULT="admin"
  DEPLOY_VMWAREUAG_SSL_VERIFY_DEFAULT="yes"
  DEPLOY_VMWAREUAG_PORT_DEFAULT="9443"

  if [ -f "${DOMAIN_CONF}" ]; then
    # shellcheck disable=SC1090
    . "${DOMAIN_CONF}"
  fi

  _debug _cdomain "${_cdomain}"
  _debug _ckey "${_ckey}"
  _debug _ccert "${_ccert}"
  _debug _cca "${_cca}"
  _debug _cfullchain "${_cfullchain}"

  # USERNAME is optional. If not provided then assume "${DEPLOY_VMWAREUAG_USERNAME_DEFAULT}"
  if [ -n "${DEPLOY_VMWAREUAG_USERNAME}" ]; then
    Le_Deploy_vmwareuag_username="${DEPLOY_VMWAREUAG_USERNAME}"
    _savedomainconf Le_Deploy_vmwareuag_username "${Le_Deploy_vmwareuag_username}"
  elif [ -z "${Le_Deploy_vmwareuag_username}" ]; then
    Le_Deploy_vmwareuag_username="${DEPLOY_VMWAREUAG_USERNAME_DEFAULT}"
  fi

  # PASSWORD is required.
  if [ -n "${DEPLOY_VMWAREUAG_PASSWORD}" ]; then
    Le_Deploy_vmwareuag_password="${DEPLOY_VMWAREUAG_PASSWORD}"
    _savedomainconf Le_Deploy_vmwareuag_password "${Le_Deploy_vmwareuag_password}"
  elif [ -z "${Le_Deploy_vmwareuag_password}" ]; then
    _err "DEPLOY_VMWAREUAG_PASSWORD is required"
    return 1
  fi

  # HOST is required.
  if [ -n "${DEPLOY_VMWAREUAG_HOST}" ]; then
    Le_Deploy_vmwareuag_host="${DEPLOY_VMWAREUAG_HOST}"
    _savedomainconf Le_Deploy_vmwareuag_host "${Le_Deploy_vmwareuag_host}"
  elif [ -z "${Le_Deploy_vmwareuag_host}" ]; then
    _err "DEPLOY_VMWAREUAG_HOST is required"
    return 1
  fi

  # SSL_VERIFY is optional. If not provided then assume "${DEPLOY_VMWAREUAG_SSL_VERIFY_DEFAULT}"
  if [ -n "${DEPLOY_VMWAREUAG_SSL_VERIFY}" ]; then
    Le_Deploy_vmwareuag_ssl_verify="${DEPLOY_VMWAREUAG_SSL_VERIFY}"
    _savedomainconf Le_Deploy_vmwareuag_ssl_verify "${Le_Deploy_vmwareuag_ssl_verify}"
  elif [ -z "${Le_Deploy_vmwareuag_ssl_verify}" ]; then
    Le_Deploy_vmwareuag_ssl_verify="${DEPLOY_VMWAREUAG_SSL_VERIFY_DEFAULT}"
  fi

  # PORT is optional. If not provided then assume "${DEPLOY_VMWAREUAG_PORT_DEFAULT}"
  if [ -n "${DEPLOY_VMWAREUAG_PORT}" ]; then
    Le_Deploy_vmwareuag_port="${DEPLOY_VMWAREUAG_PORT}"
    _savedomainconf Le_Deploy_vmwareuag_port "${Le_Deploy_vmwareuag_port}"
  elif [ -z "${Le_Deploy_vmwareuag_port}" ]; then
    Le_Deploy_vmwareuag_port="${DEPLOY_VMWAREUAG_PORT_DEFAULT}"
  fi

  # Set variables for later use
  _user="${Le_Deploy_vmwareuag_username}:${Le_Deploy_vmwareuag_password}"
  _contenttype="Content-Type: application/json"
  # shellcheck disable=SC2002
  _privatekeypem="$(cat "${_ckey}" | awk 'NF {sub(/\r/, ""); printf "%s\\n",$0;}')"
  _certchainpem="$(cat "${_ccert}" "${_cca}" | awk 'NF {sub(/\r/, ""); printf "%s\\n",$0;}')"
  _port="${Le_Deploy_vmwareuag_port}"
  _path="/rest/v1/config/certs/ssl/end_user"

  _debug _user "${_user}"
  _debug _contenttype "${_contenttype}"
  _debug _privatekeypem "${_privatekeypem}"
  _debug _certchainpem "${_certchainpem}"
  _debug _port "${_port}"
  _debug _path "${_path}"

  # Create JSON request
  _jsonreq=$(_mktemp)
  _debug _jsonreq "${_jsonreq}"
  
  printf '{ "privateKeyPem": "%s", "certChainPem": "%s" }' "${_privatekeypem}" "${_certchainpem}" >"${_jsonreq}"
  _debug JSON "$(cat "${_jsonreq}")"

  # Send request via curl
  if command -v curl; then
    _info "Using curl"
    if [ "${Le_Deploy_vmwareuag_ssl_verify}" = "yes" ]; then
      _opts=""
    else
      _opts="-k"
    fi
    _oldifs=${IFS}
    IFS=,
    for _host in ${Le_Deploy_vmwareuag_host}; do
      _url="https://${_host}:${_port}${_path}"
      _debug _url "${_url}"
      curl ${_opts} -X PUT -H "${_contenttype}" -d "@${_jsonreq}" -u "${_user}" "${_url}"
    done
    IFS=${_oldifs}
    # Remove JSON request file
    [ -f "${_jsonreq}" ] && rm -f "${_jsonreq}"
  elif command -v wget; then
    _info "Using wget"
    _err "Not implemented"
    # Remove JSON request file
    [ -f "${_jsonreq}" ] && rm -f "${_jsonreq}"
    return 1
  fi
  return 0
}
