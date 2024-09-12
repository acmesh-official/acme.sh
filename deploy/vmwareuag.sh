#!/usr/bin/env sh

# Script for acme.sh to deploy certificates to a VMware UAG appliance
#
# The following variables can be used:
#
# DEPLOY_VMWAREUAG_USERNAME="admin"   - optional
# DEPLOY_VMWAREUAG_PASSWORD=""        - required
# DEPLOY_VMWAREUAG_HOST=""            - required - host:port - comma seperated
# DEPLOY_VMWAREUAG_HTTPS_INSECURE="1" - optional - defaults to insecure
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
  DEPLOY_VMWAREUAG_HTTPS_INSECURE_DEFAULT="1"

  _debug _cdomain "${_cdomain}"
  _debug _ckey "${_ckey}"
  _debug _ccert "${_ccert}"
  _debug _cca "${_cca}"
  _debug _cfullchain "${_cfullchain}"

  # USERNAME is optional. If not provided then assume "${DEPLOY_VMWAREUAG_USERNAME_DEFAULT}"
  _getdeployconf DEPLOY_VMWAREUAG_USERNAME
  _debug2 DEPLOY_VMWAREUAG_USERNAME "${DEPLOY_VMWAREUAG_USERNAME}"
  if [ -z "${DEPLOY_VMWAREUAG_USERNAME}" ]; then
    DEPLOY_VMWAREUAG_USERNAME="${DEPLOY_VMWAREUAG_USERNAME_DEFAULT}"
  fi
  _savedeployconf DEPLOY_VMWAREUAG_USERNAME

  # PASSWORD is required.
  _getdeployconf DEPLOY_VMWAREUAG_PASSWORD
  _debug2 DEPLOY_VMWAREUAG_PASSWORD "${DEPLOY_VMWAREUAG_PASSWORD}"
  if [ -z "${DEPLOY_VMWAREUAG_PASSWORD}" ]; then
    _err "DEPLOY_VMWAREUAG_PASSWORD is required"
    return 1
  fi
  _savedeployconf DEPLOY_VMWAREUAG_PASSWORD

  # HOST is required.
  _getdeployconf DEPLOY_VMWAREUAG_HOST
  _debug2 DEPLOY_VMWAREUAG_HOST "${DEPLOY_VMWAREUAG_HOST}"
  if [ -z "${DEPLOY_VMWAREUAG_HOST}" ]; then
    _err "DEPLOY_VMWAREUAG_HOST is required"
    return 1
  fi
  _savedeployconf DEPLOY_VMWAREUAG_HOST

  # HTTPS_INSECURE is optional. If not provided then assume "${DEPLOY_VMWAREUAG_HTTPS_INSECURE_DEFAULT}"
  _getdeployconf DEPLOY_VMWAREUAG_HTTPS_INSECURE
  _debug2 DEPLOY_VMWAREUAG_HTTPS_INSECURE "${DEPLOY_VMWAREUAG_HTTPS_INSECURE}"
  if [ -z "${DEPLOY_VMWAREUAG_HTTPS_INSECURE}" ]; then
    DEPLOY_VMWAREUAG_HTTPS_INSECURE="${DEPLOY_VMWAREUAG_HTTPS_INSECURE_DEFAULT}"
  fi
  _savedeployconf DEPLOY_VMWAREUAG_HTTPS_INSECURE

  # Set variables for later use
  _user="${DEPLOY_VMWAREUAG_USERNAME}:${DEPLOY_VMWAREUAG_PASSWORD}"
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
  if [ "${DEPLOY_VMWAREUAG_HTTPS_INSECURE}" = "1" ]; then
    # shellcheck disable=SC2034
    HTTPS_INSECURE="1"
  fi

  # do post against UAG host(s)
  for _host in $(echo "${DEPLOY_VMWAREUAG_HOST}" | tr ',' ' '); do
    _url="https://${_host}${_path}"
    _debug _url "${_url}"
    _post "${_jsonreq}" "${_url}" "" "PUT" "application/json"
  done

  return 0
}
