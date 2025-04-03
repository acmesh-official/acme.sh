#!/usr/bin/bash
# Deploys a certificate to the XAPI service of the XCP-ng hypervisor.
# Further documentation: https://xcp-ng.org/docs/guides.html#tls-certificate-for-xcp-ng

XAPI_SSL_PATH="/etc/xensource/xapi-ssl.pem"
XCP_NG_BACKUP_DIR="/tmp/$(uuidgen)"

# xcp_ng_deploy deploys the new certificate to XCP-ng.
xcp_ng_deploy() {
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

  if [[ $(_xcp_ng_backup_certificate) -ne 0 ]]; then
    return 1
  fi
  _debug "Deploying certificate with 'xe host-server-certificate-install'"

  if [[ $(sudo xe host-server-certificate-install certificate="${_ccert}" private-key="${_ckey}" certificate-chain="${_cca}") -ne 0 ]]; then
    if [[ $(_xcp_ng_backup_restore) -eq 0 ]]; then
      xcp_ng_backup_delete 2>&1
    fi
    return 1
  fi
  _info "Certificate was deployed successfully."
  _xcp_ng_backup_delete 2>&1
  return 0
}

# _xcp_ng_backup_certificate saves the current certificate to a temporary folder.
# The folder can be read/ written by the current user only (chmod 600).
_xcp_ng_backup_certificate() {
  if [[ $(whoami) != "root" ]]; then
    _debug "Running as non-root user. Certificate backup not supported."
    exit 0
  fi
  _debug "Setting up temporary directory for backing up current certificate in '${XCP_NG_BACKUP_DIR}'"
  if [[ $(mkdir -m 600 "${XCP_NG_BACKUP_DIR}") -ne 0 ]]; then
    _err "Could not create temporary directory to backup the current key."
    return 1
  fi
  _debug "Moving current certificate to backup directory."
  if [[ $(mv ${XAPI_SSL_PATH} "${XCP_NG_BACKUP_DIR}") -ne 0 ]]; then
    _err "Could not move current certificate to backup directory."
    return 1
  fi
  return 0
}

# _xcp_ng_backup_restore restores the backup made by _xcp_ng_backup_certificate.
# It is called when something went wrong deploying the certificate.
_xcp_ng_backup_restore() {
  if [[ $(mv "${XCP_NG_BACKUP_DIR}/xapi-ssl.pem" "${XAPI_SSL_PATH}") -eq 0 ]]; then
    _info "Certificate restoration successful."
    return 0
  else
    _err "Certificate restoration from '${XCP_NG_BACKUP_DIR}' not possible."
    return 1
  fi
}

# _xcp_ng_backup_delete deletes the backup folder.
_xcp_ng_backup_delete() {
  if [[ $(rm -rf "${XCP_NG_BACKUP_DIR}") -eq 0 ]]; then
    _debug "Certificate backup deleted."
  else
    _err "Could not delete Backup in '${XCP_NG_BACKUP_DIR}'. Please remove it manually."
  fi
}

# _xcp_ng_xapi_restart restarts the XAPI service the certificate was deployed to.
# This is only neeeded when the old certificate had to be restored.
_xcp_ng_xapi_restart() {
  if [[ $(systemctl restart xapi) -ne 0 ]]; then
    _err "XAPI did not restart properly after deployment. Restoring old certificate for now."
    if [[ $(_xcp_ng_backup_restore) -ne 0 ]]; then
      _err "Could not restore the old certificate!!!"
    fi
    if [[ $(systemctl restart xapi) -ne 0 ]]; then
      _err "XAPI did not start after restoring the old certifiate!!!"
    fi
    return 1
  else
    _debug "XAPI was restarted successfully."
    return 0
  fi
}
