#!/usr/bin/env sh
#
# This deploy script deploys to a Sophos XG appliance
# DEPLOY_SOPHOSXG_HOST="<NO DEFAULT - REQUIRED - host:port>"
# DEPLOY_SOPHOSXG_USER="<NO DEFAULT - REQUIRED - string>"
# DEPLOY_SOPHOSXG_PASSWORD="<NO DEFAULT - REQUIRED - string>"
# DEPLOY_SOPHOSXG_NAME="domain"
# DEPLOY_SOPHOSXG_PFX_PASSWORD="s0ph0sXG"
# DEPLOY_SOPHOSXG_HTTPS_INSECURE="1"

########  Public functions #####################

#action pfx user password name pfxpass host [insecure]
sophosxg_do_req() {
  # check number of args
  [ $# -eq 8 ] || return 1

  # set vars
  _do_req_action="$1"
  _do_req_pfx="$2"
  _do_req_user="$3"
  _do_req_password="$4"
  _do_req_name="$5"
  _do_req_pfxpass="$6"
  _do_req_host="$7"
  _do_req_insecure="$8"

  # static values - as variables in case these need to change
  _do_req_boundary="SOPHOSXGPOST"
  _do_req_certfile="certificate.p12"

  # dont verify certs if config set
  if [ "${_do_req_insecure}" = "1" ]; then
    # shellcheck disable=SC2034
    HTTPS_INSECURE="1"
  fi

  # build POST body
  _do_req_post="$(printf '%s--%s\r\n' "" "${_do_req_boundary}")"
  _do_req_post="$(printf '%sContent-Type: application/xml; charset=utf-8\r\n' "${_do_req_post}")"
  _do_req_post="$(printf '%sContent-Disposition: form-data; name="reqxml"\r\n' "${_do_req_post}")"
  _do_req_post="$(printf '%s<Request>\r\n' "${_do_req_post}")"
  _do_req_post="$(printf '%s<Login>\r\n' "${_do_req_post}")"
  _do_req_post="$(printf '%s<Username>%s</Username><Password>%s</Password>\r\n' "${_do_req_post}" "${_do_req_user}" "${_do_req_password}")"
  _do_req_post="$(printf '%s</Login>\r\n' "${_do_req_post}")"
  _do_req_post="$(printf '%s<Set operation="%s">\r\n' "${_do_req_post}" "${_do_req_action}")"
  _do_req_post="$(printf '%s<Certificate>\r\n' "${_do_req_post}")"
  _do_req_post="$(printf '%s<Name>%s</Name>\r\n' "${_do_req_post}" "${_do_req_name}")"
  _do_req_post="$(printf '%s<Action>UploadCertificate</Action>\r\n' "${_do_req_post}")"
  _do_req_post="$(printf '%s<CertificateFormat>pkcs12</CertificateFormat>\r\n' "${_do_req_post}")"
  _do_req_post="$(printf '%s<Password>%s</Password>\r\n' "${_do_req_post}" "${_do_req_pfxpass}")"
  _do_req_post="$(printf '%s<CertificateFile>%s</CertificateFile>\r\n' "${_do_req_post}" "${_do_req_certfile}")"
  _do_req_post="$(printf '%s</Certificate>\r\n' "${_do_req_post}")"
  _do_req_post="$(printf '%s</Set>\r\n' "${_do_req_post}")"
  _do_req_post="$(printf '%s</Request>\r\n' "${_do_req_post}")"
  _do_req_post="$(printf '%s--%s\r\n' "${_do_req_post}" "${_do_req_boundary}")"
  _do_req_post="$(printf '%sContent-Type: application/octet-stream\r\n' "${_do_req_post}")"
  _do_req_post="$(printf '%sContent-Disposition: form-data; filename="%s"; name="file"\r\n' "${_do_req_post}" "${_do_req_certfile}")"
  _do_req_post="$(printf '%s%s\r\n' "${_do_req_post}" "$(_base64 <"${_do_req_pfx}")")"
  _do_req_post="$(printf '%s--%s--\r\n' "${_do_req_post}" "${_do_req_boundary}")"

  # do POST
  _post "${_do_req_post}" "https://${_do_req_host}/webconsole/APIController?" "" "POST" "multipart/form-data; boundary=${_do_req_boundary}"
}

#domain keyfile certfile cafile fullchain
sophosxg_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"

  # Some defaults
  DEFAULT_SOPHOSXG_PFX_PASSWORD="s0ph0sXG"
  DEFAULT_SOPHOSXG_NAME="$_cdomain"
  DEFAULT_SOPHOSXG_HTTPS_INSECURE="1"

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"

  # HOST is required
  _getdeployconf DEPLOY_SOPHOSXG_HOST
  _devug2 DEPLOY_SOPHOSXG_HOST "${DEPLOY_SOPHOSXG_HOST}"
  if [ -z "${DEPLOY_SOPHOSXG_HOST}" ]; then
    _err "DEPLOY_SOPHOSXG_HOST not defined."
    return 1
  fi
  _savedeployconf DEPLOY_SOPHOSXG_HOST "${DEPLOY_SOPHOSXG_HOST}"

  # USER is required
  _getdeployconf DEPLOY_SOPHOSXG_USER
  _devug2 DEPLOY_SOPHOSXG_USER "${DEPLOY_SOPHOSXG_USER}"
  if [ -z "${DEPLOY_SOPHOSXG_USER}" ]; then
    _err "DEPLOY_SOPHOSXG_USER not defined."
    return 1
  fi
  _savedeployconf DEPLOY_SOPHOSXG_USER "${DEPLOY_SOPHOSXG_USER}"

  # PASSWORD is required
  _getdeployconf DEPLOY_SOPHOSXG_PASSWORD
  _devug2 DEPLOY_SOPHOSXG_PASSWORD "${DEPLOY_SOPHOSXG_PASSWORD}"
  if [ -z "${DEPLOY_SOPHOSXG_PASSWORD}" ]; then
    _err "DEPLOY_SOPHOSXG_PASSWORD not defined."
    return 1
  fi
  _savedeployconf DEPLOY_SOPHOSXG_PASSWORD "${DEPLOY_SOPHOSXG_PASSWORD}"

  # PFX_PASSWORD is optional. If not provided then use default
  _getdeployconf DEPLOY_SOPHOSXG_PFX_PASSWORD
  _devug2 DEPLOY_SOPHOSXG_PFX_PASSWORD "${DEPLOY_SOPHOSXG_PFX_PASSWORD}"
  if [ -z "${DEPLOY_SOPHOSXG_PFX_PASSWORD}" ]; then
    DEPLOY_SOPHOSXG_PFX_PASSWORD="${DEFAULT_SOPHOSXG_PFX_PASSWORD}"
  fi
  _savedeployconf DEPLOY_SOPHOSXG_PFX_PASSWORD "${DEPLOY_SOPHOSXG_PFX_PASSWORD}"

  # NAME is optional. If not provided then use $_cdomain
  _getdeployconf DEPLOY_SOPHOSXG_NAME
  _devug2 DEPLOY_SOPHOSXG_NAME "${DEPLOY_SOPHOSXG_NAME}"
  if [ -z "${DEPLOY_SOPHOSXG_NAME}" ]; then
    DEPLOY_SOPHOSXG_NAME="${DEFAULT_SOPHOSXG_NAME}"
  fi
  _savedeployconf DEPLOY_SOPHOSXG_NAME "${DEPLOY_SOPHOSXG_NAME}"

  # HTTPS_INSECURE is optional. Defaults to 1 (true)
  _getdeployconf DEPLOY_SOPHOSXG_HTTPS_INSECURE
  _devug2 DEPLOY_SOPHOSXG_HTTPS_INSECURE "${DEPLOY_SOPHOSXG_HTTPS_INSECURE}"
  if [ -z "${DEPLOY_SOPHOSXG_HTTPS_INSECURE}" ]; then
    DEPLOY_SOPHOSXG_HTTPS_INSECURE="${DEFAULT_SOPHOSXG_HTTPS_INSECURE}"
  fi
  _savedeployconf DEPLOY_SOPHOSXG_HTTPS_INSECURE "${DEPLOY_SOPHOSXG_HTTPS_INSECURE}"

  # create temp pkcs12 file
  _info "Generating pkcs12 file"
  _import_pkcs12="$(_mktemp)"
  if [ ! -f "$_import_pkcs12" ]; then
    _err "Error creating temp file for pkcs12"
    return 1
  fi
  if ! _toPkcs "$_import_pkcs12" "$_ckey" "$_ccert" "$_cca" "$DEPLOY_SOPHOSXG_PFX_PASSWORD"; then
    _err "Error exporting to pkcs12"
    [ -f "$_import_pkcs12" ] && rm -f "$_import_pkcs12"
    return 1
  fi

  # do upload of cert via HTTP POST - attempt to "update" and on failure try "add"
  _req_action_success="no"
  for _req_action in update add; do
    _info "Uploading certificate: $_req_action"
    if sophosxg_do_req "$_req_action" "$_import_pkcs12" "$DEPLOY_SOPHOSXG_USER" "$DEPLOY_SOPHOSXG_PASSWORD" "$DEPLOY_SOPHOSXG_NAME" "$DEPLOY_SOPHOSXG_PFX_PASSWORD" "$DEPLOY_SOPHOSXG_HOST" "$DEPLOY_SOPHOSXG_HTTPS_INSECURE"; then
      _req_action_success="yes"
      break
    fi
    _info "$_req_action failed"
  done

  # clean up pfx
  [ -f "$_import_pkcs12" ] && rm -f "$_import_pkcs12"

  # check final result
  if [ "$_req_action_success" = "no" ]; then
    _err "Upload failed permanently"
    return 1
  fi

  return 0

}
