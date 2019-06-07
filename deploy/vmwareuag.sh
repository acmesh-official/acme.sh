#!/usr/bin/env sh

# Script for acme.sh to deploy certificates to a VMware UAG appliance
#
# The following variables can be used:
#
# export DEPLOY_VMWAREUAG_USERNAME="admin"   - optional
# export DEPLOY_VMWAREUAG_PASSWORD=""        - required
# export DEPLOY_VMWAREUAG_HOST=""            - required - host:port - comma seperated list 
# export DEPLOY_VMWAREUAG_HTTPS_INSECURE="1" - optional - defaults to insecure
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
  # convert key and fullchain into "single line pem" for JSON request
  _privatekeypem="$(tr '\n' '\000' <"${_ckey}" | sed 's/\x0/\\n/g')"
  _certchainpem="$(tr '\n' '\000' <"${_cfullchain}" | sed 's/\x0/\\n/g')"
  # api path
  _path="/rest/v1/config/certs/ssl/end_user"

  _debug _user "${_user}"
  _debug _privatekeypem "${_privatekeypem}"
  _debug _certchainpem "${_certchainpem}"
  _debug _path "${_path}"

  # Create JSON request
  _jsonreq="$(printf '{ "privateKeyPem": "%s", "certChainPem": "%s" }' "${_privatekeypem}" "${_certchainpem}")"
  _debug _jsonreq "${_jsonreq}"

  # dont verify certs if config set
  if [ "${Le_Deploy_vmwareuag_https_insecure}" = "1" ]; then
    # shellcheck disable=SC2034
    HTTPS_INSECURE="1"
  fi

  # do post against UAG host(s)
  for _host in $(echo "${Le_Deploy_vmwareuag_host}" | tr ',' ' '); do
    _url="https://${_host}${_path}"
    _debug _url "${_url}"
    _post "${_jsonreq}" "${_url}" "" "PUT" "application/json"
  done

  return 0
}
