#!/usr/bin/env sh

# Script for acme.sh to deploy certificates to a VMware UAG appliance
#
# The following variables can be exported:
#
# export DEPLOY_VMWAREUAG_USERNAME="admin"
# export DEPLOY_VMWAREUAG_PASSWORD=""        - required
# export DEPLOY_VMWAREUAG_HOST=""            - required (space seperated list) host:port
# export DEPLOY_VMWAREUAG_HTTPS_INSECURE="1" - defaults to insecure
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
  DEPLOY_VMWAREUAG_HTTPS_INSECURE="1"

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

  # HTTPS_INSECURE is optional. If not provided then assume "${DEPLOY_VMWAREUAG_HTTPS_INSECURE_DEFAULT}"
  if [ -n "${DEPLOY_VMWAREUAG_HTTPS_INSECURE}" ]; then
    Le_Deploy_vmwareuag_https_insecure="${DEPLOY_VMWAREUAG_HTTPS_INSECURE}"
    _savedomainconf Le_Deploy_vmwareuag_https_insecure "${Le_Deploy_vmwareuag_https_insecure}"
  elif [ -z "${Le_Deploy_vmwareuag_https_insecure}" ]; then
    Le_Deploy_vmwareuag_https_insecure="${DEPLOY_VMWAREUAG_HTTPS_INSECURE}"
  fi

  # Set variables for later use
  _user="${Le_Deploy_vmwareuag_username}:${Le_Deploy_vmwareuag_password}"
  _privatekeypem="$(awk 'NF {sub(/\r/, ""); printf "%s\\n",$0;}' <"${_ckey}")"
  _certchainpem="$(awk 'NF {sub(/\r/, ""); printf "%s\\n",$0;}' <"${_cfullchain}")"
  _path="/rest/v1/config/certs/ssl/end_user"

  _debug _user "${_user}"
  _debug _privatekeypem "${_privatekeypem}"
  _debug _certchainpem "${_certchainpem}"
  _debug _path "${_path}"

  # Create JSON request
  _jsonreq="$(printf '{ "privateKeyPem": "%s", "certChainPem": "%s" }' "${_privatekeypem}" "${_certchainpem}")"
  _debug JSON "${_jsonreq}"

  # dont verify certs if config set
  _old_HTTPS_INSECURE="${HTTPS_INSECURE}"
  if [ "${Le_Deploy_vmwareuag_https_insecure}" = "1" ]; then
    HTTPS_INSECURE="1"
  fi

  # do post against UAG host(s)
  for _host in ${Le_Deploy_vmwareuag_host}; do
    _url="https://${_host}${_path}"
    _debug _url "${_url}"
    _post "${_jsonreq}" "${_url}" "" "PUT" "application/json"
  done

  # reset HTTP_INSECURE
  HTTPS_INSECURE="${_old_HTTPS_INSECURE}"

  return 0
}
