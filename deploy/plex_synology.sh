#!/usr/bin/bash

# Here is a script to deploy cert to local Plex Media Server on Synology.
# Based on https://www.snbforums.com/threads/issue-lets-encrypt-certificate-with-acme-sh-use-it-with-synology-dsm-and-plex.70395/

# The following environment variables must be set:
#
# PLEX_PKCS12_Password - Password used for the PKCS12 certificate

#returns 0 means success, otherwise error.

# Settings for Plex Media Server:
#
# PLEX_PKCS12_password -- Password for the PKCS file. Required by plex
# PLEX_PKCS12_file -- Full PKCS file location, otherwise defaults to placing with the other certs in that domain with a pfx extension
# PLEX_sudo_required -- 1 = True, 0 = False. You may need to add "plex ALL=(ALL) NOPASSWD:/bin/systemctl restart plexmediaserver.service" to your sudo'ers file

# Set Plex certificate location to /usr/local/share/Plex/plex_cert.pfx

########  Public functions #####################

#domain keyfile certfile cafile fullchain
plex_synology_deploy() {
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

  _getdeployconf PLEX_PKCS12_password
  _getdeployconf PLEX_PKCS12_file
  _getdeployconf PLEX_sudo_required

  #_DEPLOY_PLEX_WIKI="https://github.com/acmesh-official/acme.sh/wiki/deploy-to-plex"

  _plex_to_pkcs() {
    # The existing _toPkcs command doesn't have an option to specify cipher, so copied here
    # to force using a modern cipher, as required by PMS:
    # https://forums.plex.tv/t/ssl-became-broken-after-latest-pms-update/837416/4
    _cpfx="$1"
    _ckey="$2"
    _ccert="$3"
    _cca="$4"
    pfxPassword="$5"

    ${ACME_OPENSSL_BIN:-openssl} pkcs12 -export -out "$_cpfx" -certpbe AES-256-CBC -keypbe AES-256-CBC -macalg SHA256 -inkey "$_ckey" -in "$_ccert" -certfile "$_cca" -password "pass:$pfxPassword"
  }

  if [ -z "$PLEX_PKCS12_password" ]; then
    _err "The PLEX_PKCS12_password variable is not defined. Plex requires a password for the certificate."
    #_err "See: $_DEPLOY_PLEX_WIKI"
    return 1
  fi
  _debug2 PLEX_PKCS12_password "$PLEX_PKCS12_password"

  if [ -z "$PLEX_PKCS12_file" ]; then
    PLEX_PKCS12_file="/usr/local/share/Plex/plex_cert.pfx"
    _debug2 "Setting PLEX_PKCS12_file to default"
  fi
  _debug2 PLEX_PKCS12_file "$PLEX_PKCS12_file"

  if [ -z "$PLEX_sudo_required" ]; then
    PLEX_sudo_required=0
    _debug2 "Setting PLEX_PKCS12_file to default (0/False)"
  fi

  _debug2 PLEX_sudo_required "$PLEX_sudo_required"

  _reload_cmd=""

  _debug "Generate import pkcs12"

  if ! _plex_to_pkcs "$PLEX_PKCS12_file" "$_ckey" "$_ccert" "$_cca" "$PLEX_PKCS12_password"; then
    _err "Error generating pkcs12. Please re-run with --debug and report a bug."
    return 1
  fi

  if systemctl -q is-active pkgctl-PlexMediaServer.service; then
    _debug2 "Plex is active. Restarting..."
    _reload_cmd="/usr/syno/bin/synopkg restart PlexMediaServer"
  fi
  if [ -z "$_reload_cmd" ]; then
    _info "Plex server is not active. Certificates installed, but skipping restart."
  else
    if eval "$_reload_cmd"; then
      _info "Reload success!"
    else
      _err "Reload error"
      return 1
    fi
  fi

  _services_updated="${_services_updated} plexmediaserver"
  _info "Install Plex Media Server certificate success!"

  # Successful, so save all (non-default) config:
  _savedeployconf PLEX_PKCS12_password "$PLEX_PKCS12_password"
  _savedeployconf PLEX_PKCS12_file "$PLEX_PKCS12_file"
  _savedeployconf PLEX_sudo_required "$PLEX_sudo_required"

  return 0
}
