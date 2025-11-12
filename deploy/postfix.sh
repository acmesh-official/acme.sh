#!/usr/bin/env sh

# Script for acme.sh to deploy certificates to postfix
#
# The following variables can be exported:
#
# export DEPLOY_POSTFIX_PEM_PATH="/etc/postfix/cert"
#
# Defines location of PEM file for Postfix.
# Defaults to /etc/postfix/cert
#
# export DEPLOY_POSTFIX_PEM_NAME="${domain}.pem"
#
# Defines the name of the PEM file.
# Defaults to "<domain>.pem"
#
# export DEPLOY_POSTFIX_RELOAD="sudo systemctl reload postfix"
#
# You may need to edit sudoers to allow acme user to relaod
# 
# OPTIONAL: Reload command used post deploy
# This defaults to be a no-op (ie "true").
# It is strongly recommended to set this something that makes sense
# for your distro.

########  Public functions #####################

postfix_deploy(){
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"

  # Some defaults
  DEPLOY_POSTFIX_PEM_PATH_DEFAULT="/etc/postfix/cert"
  DEPLOY_POSTFIX_PEM_NAME_DEFAULT="${_cdomain}.pem"
  DEPLOY_POSTFIX_RELOAD_DEFAULT="true"

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"

  _getdeployconf DEPLOY_POSTFIX_PEM_PATH

  # PEM_PATH is optional. If not provided then assume "${DEPLOY_POSTFIX_PEM_PATH_DEFAULT}"
  if [ -n "$DEPLOY_POSTFIX_PEM_PATH" ]; then
    Le_Deploy_postfix_pem_path="$DEPLOY_POSTFIX_PEM_PATH"
    _savedomainconf Le_Deploy_postfix_pem_path "$Le_Deploy_postfix_pem_path"
  elif [ -z "$Le_Deploy_postfix_pem_path" ]; then
    Le_Deploy_postfix_pem_path="$DEPLOY_POSTFIX_PEM_PATH_DEFAULT"
  fi

  # Ensure PEM_PATH exists
  if [ -d "${Le_Deploy_postfix_pem_path}" ]; then
    _debug "PEM_PATH ${Le_Deploy_postfix_pem_path} exists"
  else
    _err "PEM_PATH ${Le_Deploy_postfix_pem_path} does not exist"
    return 1
  fi

  # PEM_NAME is optional. If not provided then assume "${DEPLOY_POSTFIX_PEM_NAME_DEFAULT}"
  _getdeployconf DEPLOY_POSTFIX_PEM_NAME
  _debug2 DEPLOY_POSTFIX_PEM_NAME "${DEPLOY_POSTFIX_PEM_NAME}"
  
  # Was the environment variable explicitly set (even if empty)?
  if [ -n "${DEPLOY_POSTFIX_PEM_NAME+x}" ]; then
    _env_has_pem_name=1
  else
    _env_has_pem_name=0
  fi

  if [ "$_env_has_pem_name" -eq 1 ]; then
    if [ -n "${DEPLOY_POSTFIX_PEM_NAME}" ]; then
      # ENV is non-empty, use it and save it
      Le_Deploy_postfix_pem_name="${DEPLOY_POSTFIX_PEM_NAME}"
      _savedomainconf Le_Deploy_postfix_pem_name "${Le_Deploy_postfix_pem_name}"
    else
      # ENV explicitly empty, reset to default, clear saved value
      Le_Deploy_postfix_pem_name="${DEPLOY_POSTFIX_PEM_NAME_DEFAULT}"
      _cleardomainconf Le_Deploy_postfix_pem_name 2>/dev/null || true
    fi
  elif [ -z "${Le_Deploy_postfix_pem_name}" ]; then
    Le_Deploy_postfix_pem_name="${DEPLOY_POSTFIX_PEM_NAME_DEFAULT}"
    # We better not have '*' as the first character
    if [ "${Le_Deploy_postfix_pem_name%%"${Le_Deploy_postfix_pem_name#?}"}" = '*' ]; then
      # removes the first characters and add a _ instead
      Le_Deploy_postfix_pem_name="_${Le_Deploy_postfix_pem_name#?}"
    fi
  fi

  # RELOAD is optional. If not provided then assume "${DEPLOY_POSTFIX_RELOAD_DEFAULT}"
  _getdeployconf DEPLOY_POSTFIX_RELOAD
  _debug2 DEPLOY_POSTFIX_RELOAD "${DEPLOY_POSTFIX_RELOAD}"
  if [ -n "${DEPLOY_POSTFIX_RELOAD}" ]; then
    Le_Deploy_postfix_reload="${DEPLOY_POSTFIX_RELOAD}"
    _savedomainconf Le_Deploy_postfix_reload "${Le_Deploy_postfix_reload}"
  elif [ -z "${Le_Deploy_postfix_reload}" ]; then
    Le_Deploy_postfix_reload="${DEPLOY_POSTFIX_RELOAD_DEFAULT}"
  fi

  # Set variables for later
  _pem="${Le_Deploy_postfix_pem_path}/${Le_Deploy_postfix_pem_name}"
  _reload="${Le_Deploy_postfix_reload}"

  _info "Deploying PEM file"
  # Create a temporary PEM file
  _temppem="$(_mktemp)"
  _debug _temppem "${_temppem}"
  cat "${_ckey}" "${_ccert}" "${_cca}" | grep . >"${_temppem}"
  _ret="$?"

  # Check that we could create the temporary file
  if [ "${_ret}" != "0" ]; then
    _err "Error code ${_ret} returned during PEM file creation"
    [ -f "${_temppem}" ] && rm -f "${_temppem}"
    return ${_ret}
  fi

  # Move PEM file into place
  _info "Moving new certificate into place"
  _debug _pem "${_pem}"
  : "${DEPLOY_POSTFIX_PEM_MODE:=0640}"
  chmod "${DEPLOY_POSTFIX_PEM_MODE}" "${_temppem}" 2>/dev/null || true
  mv "${_temppem}" "${_pem}" || {
    # Deal with any failure of moving PEM file into place
    _err "Failed to move new certificate into place"
    [ -f "${_temppem}" ] && rm -f "${_temppem}"
    return 1
  }

  # Reload Postfix
  _debug _reload "${_reload}"
  eval "${_reload}"
  _ret=$?
  if [ "${_ret}" != "0" ]; then
    _err "Error code ${_ret} during reload"
    return ${_ret}
  else
    _info "Reload successful"
  fi

  return 0
}
