#!/usr/bin/env sh

# Here is a script to deploy cert on a Unifi Controller or Cloud Key device.
# It supports:
#   - self-hosted Unifi Controller
#   - Unifi Cloud Key Gen1
#   - UnifiOS (Cloud Key Gen2)
# Please report bugs to https://github.com/acmesh-official/acme.sh/issues/3359

#returns 0 means success, otherwise error.

# The deploy-hook automatically detects standard Unifi installations
# for each of the supported environments. Most users should not need
# to set any of these variables, but if you are running a self-hosted
# Controller with custom locations, set these as necessary before running
# the deploy hook. (Defaults shown below.)
#
# Settings for Unifi Controller:
# Location of Java keystore or unifi.keystore.jks file:
#DEPLOY_UNIFI_KEYSTORE="/usr/lib/unifi/data/keystore"
# Keystore password (built into Unifi Controller, not a user-set password):
#DEPLOY_UNIFI_KEYPASS="aircontrolenterprise"
# Command to restart Unifi Controller:
#DEPLOY_UNIFI_RELOAD="service unifi restart"
#
# Settings for Unifi Cloud Key Gen1 (nginx admin pages):
# Directory where cloudkey.crt and cloudkey.key live:
#DEPLOY_UNIFI_CLOUDKEY_CERTDIR="/etc/ssl/private"
# Command to restart maintenance pages and Controller
# (same setting as above, default is updated when running on Cloud Key Gen1):
#DEPLOY_UNIFI_RELOAD="service nginx restart && service unifi restart"
#
# Settings for UnifiOS (Cloud Key Gen2):
# Directory where unifi-core.crt and unifi-core.key live:
#DEPLOY_UNIFI_CORE_CONFIG="/data/unifi-core/config/"
# Command to restart unifi-core:
#DEPLOY_UNIFI_RELOAD="systemctl restart unifi-core"
#
# At least one of DEPLOY_UNIFI_KEYSTORE, DEPLOY_UNIFI_CLOUDKEY_CERTDIR,
# or DEPLOY_UNIFI_CORE_CONFIG must exist to receive the deployed certs.

########  Public functions #####################

#domain keyfile certfile cafile fullchain
unifi_deploy() {
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

  # Default reload commands are accumulated in an &&-separated string
  # as we auto-detect environments:
  DEFAULT_UNIFI_RELOAD=""

  # Unifi Controller (self-hosted or Cloud Key Gen1) environment --
  # auto-detect by file /usr/lib/unifi/data/keystore:
  DEFAULT_UNIFI_KEYSTORE="/usr/lib/unifi/data/keystore"
  _unifi_keystore="${DEPLOY_UNIFI_KEYSTORE:-$DEFAULT_UNIFI_KEYSTORE}"
  if [ -f "$_unifi_keystore" ]; then
    _info "Installing certificate for Unifi Controller (Java keystore)"
    _debug _unifi_keystore "$_unifi_keystore"
    if ! _exists keytool; then
      _err "keytool not found"
      return 1
    fi
    if [ ! -w "$_unifi_keystore" ]; then
      _err "The file $_unifi_keystore is not writable, please change the permission."
      return 1
    fi

    DEFAULT_UNIFI_KEYPASS="aircontrolenterprise"
    _unifi_keypass="${DEPLOY_UNIFI_KEYPASS:-$DEFAULT_UNIFI_KEYPASS}"

    _debug "Generate import pkcs12"
    _import_pkcs12="$(_mktemp)"
    _toPkcs "$_import_pkcs12" "$_ckey" "$_ccert" "$_cca" "$_unifi_keypass" unifi root
    # shellcheck disable=SC2181
    if [ "$?" != "0" ]; then
      _err "Oops, error creating import pkcs12, please report bug to us."
      return 1
    fi

    _debug "Import into keystore: $_unifi_keystore"
    if keytool -importkeystore \
      -deststorepass "$_unifi_keypass" -destkeypass "$_unifi_keypass" -destkeystore "$_unifi_keystore" \
      -srckeystore "$_import_pkcs12" -srcstoretype PKCS12 -srcstorepass "$_unifi_keypass" \
      -alias unifi -noprompt; then
      _debug "Import keystore success!"
      rm "$_import_pkcs12"
    else
      _err "Error importing into Unifi Java keystore."
      _err "Please re-run with --debug and report a bug."
      rm "$_import_pkcs12"
      return 1
    fi

    DEFAULT_UNIFI_RELOAD="${DEFAULT_UNIFI_RELOAD} ${DEFAULT_UNIFI_RELOAD:+&&} service unifi restart"
    _info "Install Unifi Controller certificate success!"
  elif [ "$DEPLOY_UNIFI_KEYSTORE" ]; then
    _err "The specified DEPLOY_UNIFI_KEYSTORE='$DEPLOY_UNIFI_KEYSTORE' is not valid, please check."
    return 1
  fi

  # Cloud Key Gen1 environment (nginx admin pages) --
  # auto-detect by file /etc/ssl/private/cloudkey.key:
  DEFAULT_DEPLOY_UNIFI_CLOUDKEY_CERTDIR="/etc/ssl/private"
  _cloudkey_certdir="${DEPLOY_UNIFI_CLOUDKEY_CERTDIR:-$DEFAULT_DEPLOY_UNIFI_CLOUDKEY_CERTDIR}"
  if [ -f "${_cloudkey_certdir}/cloudkey.key" ]; then
    _info "Installing certificate for Cloud Key Gen1 (nginx admin pages)"
    _debug _cloudkey_certdir "$_cloudkey_certdir"
    if [ ! -w "$_cloudkey_certdir" ]; then
      _err "The directory $_cloudkey_certdir is not writable; please check permissions."
      return 1
    fi

    cp "$_cfullchain" "${_cloudkey_certdir}/cloudkey.crt"
    cp "$_ckey" "${_cloudkey_certdir}/cloudkey.key"
    (cd "$_cloudkey_certdir" && tar -cf cert.tar cloudkey.crt cloudkey.key unifi.keystore.jks)
    _info "Install Cloud Key Gen1 certificate success!"

    DEFAULT_UNIFI_RELOAD="${DEFAULT_UNIFI_RELOAD} ${DEFAULT_UNIFI_RELOAD:+&&} service nginx restart"
  elif [ "$DEPLOY_UNIFI_CLOUDKEY_CERTDIR" ]; then
    _err "The specified DEPLOY_UNIFI_CLOUDKEY_CERTDIR='$DEPLOY_UNIFI_CLOUDKEY_CERTDIR' is not valid, please check."
    return 1
  fi

  # UnifiOS environment -- auto-detect by /data/unifi-core/config/unifi-core.key:
  DEFAULT_DEPLOY_UNIFI_CORE_CONFIG="/etc/ssl/private"
  _unifi_core_config="${DEPLOY_UNIFI_CORE_CONFIG:-$DEFAULT_DEPLOY_UNIFI_CORE_CONFIG}"
  if [ -f "${_unifi_core_config}/unifi-core.key" ]; then
    _info "Installing certificate for UnifiOS"
    _debug _unifi_core_config "$_unifi_core_config"
    if [ ! -w "$_unifi_core_config" ]; then
      _err "The directory $_unifi_core_config is not writable; please check permissions."
      return 1
    fi

    cp "$_cfullchain" "${_unifi_core_config}/unifi-core.crt"
    cp "$_ckey" "${_unifi_core_config}/unifi-core.key"
    _info "Install UnifiOS certificate success!"

    DEFAULT_UNIFI_RELOAD="${DEFAULT_UNIFI_RELOAD} ${DEFAULT_UNIFI_RELOAD:+&&} systemctl restart unifi-core"
  elif [ "$DEPLOY_UNIFI_CORE_CONFIG" ]; then
    _err "The specified DEPLOY_UNIFI_CORE_CONFIG='$DEPLOY_UNIFI_CORE_CONFIG' is not valid, please check."
    return 1
  fi

  if [ -z "$DEFAULT_UNIFI_RELOAD" ]; then
    # None of the Unifi environments were auto-detected, so no deployment has occurred
    # (and none of DEPLOY_UNIFI_{KEYSTORE,CLOUDKEY_CERTDIR,CORE_CONFIG} were set).
    _err "Unable to detect Unifi environment in standard location."
    _err "(This deploy hook must be run on the Unifi device, not a remote machine.)"
    _err "For non-standard Unifi installations, set DEPLOY_UNIFI_KEYSTORE,"
    _err "DEPLOY_UNIFI_CLOUDKEY_CERTDIR, and/or DEPLOY_UNIFI_CORE_CONFIG as appropriate."
    return 1
  fi

  _reload="${DEPLOY_UNIFI_RELOAD:-$DEFAULT_UNIFI_RELOAD}"
  _info "Reload services (this may take some time): $_reload"
  if eval "$_reload"; then
    _info "Reload success!"
  else
    _err "Reload error"
    return 1
  fi

  # Successful, so save all config:
  if [ "$DEPLOY_UNIFI_KEYSTORE" ]; then
    _savedomainconf DEPLOY_UNIFI_KEYSTORE "$DEPLOY_UNIFI_KEYSTORE"
  else
    _cleardomainconf DEPLOY_UNIFI_KEYSTORE
  fi
  if [ "$DEPLOY_UNIFI_KEYPASS" ]; then
    _savedomainconf DEPLOY_UNIFI_KEYPASS "$DEPLOY_UNIFI_KEYPASS"
  else
    _cleardomainconf DEPLOY_UNIFI_KEYPASS
  fi
  if [ "$DEPLOY_UNIFI_CLOUDKEY_CERTDIR" ]; then
    _savedomainconf DEPLOY_UNIFI_CLOUDKEY_CERTDIR "$DEPLOY_UNIFI_CLOUDKEY_CERTDIR"
  else
    _cleardomainconf DEPLOY_UNIFI_CLOUDKEY_CERTDIR
  fi
  if [ "$DEPLOY_UNIFI_CORE_CONFIG" ]; then
    _savedomainconf DEPLOY_UNIFI_CORE_CONFIG "$DEPLOY_UNIFI_CORE_CONFIG"
  else
    _cleardomainconf DEPLOY_UNIFI_CORE_CONFIG
  fi
  if [ "$DEPLOY_UNIFI_RELOAD" ]; then
    _savedomainconf DEPLOY_UNIFI_RELOAD "$DEPLOY_UNIFI_RELOAD"
  else
    _cleardomainconf DEPLOY_UNIFI_RELOAD
  fi

  return 0
}
