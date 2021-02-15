#!/usr/bin/env sh

# Here is a script to deploy cert on a Unifi Controller or Cloud Key device.
# It supports:
#   - self-hosted Unifi Controller
#   - Unifi Cloud Key (Gen1/2/2+)
#   - Unifi Cloud Key running UnifiOS (v2.0.0+, Gen2/2+ only)
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

  _getdeployconf DEPLOY_UNIFI_KEYSTORE
  _getdeployconf DEPLOY_UNIFI_KEYPASS
  _getdeployconf DEPLOY_UNIFI_CLOUDKEY_CERTDIR
  _getdeployconf DEPLOY_UNIFI_CORE_CONFIG
  _getdeployconf DEPLOY_UNIFI_RELOAD

  _debug2 DEPLOY_UNIFI_KEYSTORE "$DEPLOY_UNIFI_KEYSTORE"
  _debug2 DEPLOY_UNIFI_KEYPASS "$DEPLOY_UNIFI_KEYPASS"
  _debug2 DEPLOY_UNIFI_CLOUDKEY_CERTDIR "$DEPLOY_UNIFI_CLOUDKEY_CERTDIR"
  _debug2 DEPLOY_UNIFI_CORE_CONFIG "$DEPLOY_UNIFI_CORE_CONFIG"
  _debug2 DEPLOY_UNIFI_RELOAD "$DEPLOY_UNIFI_RELOAD"

  # Space-separated list of environments detected and installed:
  _services_updated=""

  # Default reload commands accumulated as we auto-detect environments:
  _reload_cmd=""

  # Unifi Controller environment (self hosted or any Cloud Key) --
  # auto-detect by file /usr/lib/unifi/data/keystore:
  _unifi_keystore="${DEPLOY_UNIFI_KEYSTORE:-/usr/lib/unifi/data/keystore}"
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

    _unifi_keypass="${DEPLOY_UNIFI_KEYPASS:-aircontrolenterprise}"

    _debug "Generate import pkcs12"
    _import_pkcs12="$(_mktemp)"
    _toPkcs "$_import_pkcs12" "$_ckey" "$_ccert" "$_cca" "$_unifi_keypass" unifi root
    # shellcheck disable=SC2181
    if [ "$?" != "0" ]; then
      _err "Error generating pkcs12. Please re-run with --debug and report a bug."
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

    if systemctl -q is-active unifi; then
      _reload_cmd="${_reload_cmd:+$_reload_cmd && }service unifi restart"
    fi
    _services_updated="${_services_updated} unifi"
    _info "Install Unifi Controller certificate success!"
  elif [ "$DEPLOY_UNIFI_KEYSTORE" ]; then
    _err "The specified DEPLOY_UNIFI_KEYSTORE='$DEPLOY_UNIFI_KEYSTORE' is not valid, please check."
    return 1
  fi

  # Cloud Key environment (non-UnifiOS -- nginx serves admin pages) --
  # auto-detect by file /etc/ssl/private/cloudkey.key:
  _cloudkey_certdir="${DEPLOY_UNIFI_CLOUDKEY_CERTDIR:-/etc/ssl/private}"
  if [ -f "${_cloudkey_certdir}/cloudkey.key" ]; then
    _info "Installing certificate for Cloud Key Gen1 (nginx admin pages)"
    _debug _cloudkey_certdir "$_cloudkey_certdir"
    if [ ! -w "$_cloudkey_certdir" ]; then
      _err "The directory $_cloudkey_certdir is not writable; please check permissions."
      return 1
    fi
    # Cloud Key expects to load the keystore from /etc/ssl/private/unifi.keystore.jks.
    # Normally /usr/lib/unifi/data/keystore is a symlink there (so the keystore was
    # updated above), but if not, we don't know how to handle this installation:
    if ! cmp -s "$_unifi_keystore" "${_cloudkey_certdir}/unifi.keystore.jks"; then
      _err "Unsupported Cloud Key configuration: keystore not found at '${_cloudkey_certdir}/unifi.keystore.jks'"
      return 1
    fi

    cat "$_cfullchain" >"${_cloudkey_certdir}/cloudkey.crt"
    cat "$_ckey" >"${_cloudkey_certdir}/cloudkey.key"
    (cd "$_cloudkey_certdir" && tar -cf cert.tar cloudkey.crt cloudkey.key unifi.keystore.jks)

    if systemctl -q is-active nginx; then
      _reload_cmd="${_reload_cmd:+$_reload_cmd && }service nginx restart"
    fi
    _info "Install Cloud Key Gen1 certificate success!"
    _services_updated="${_services_updated} nginx"
  elif [ "$DEPLOY_UNIFI_CLOUDKEY_CERTDIR" ]; then
    _err "The specified DEPLOY_UNIFI_CLOUDKEY_CERTDIR='$DEPLOY_UNIFI_CLOUDKEY_CERTDIR' is not valid, please check."
    return 1
  fi

  # UnifiOS environment -- auto-detect by /data/unifi-core/config/unifi-core.key:
  _unifi_core_config="${DEPLOY_UNIFI_CORE_CONFIG:-/data/unifi-core/config}"
  if [ -f "${_unifi_core_config}/unifi-core.key" ]; then
    _info "Installing certificate for UnifiOS"
    _debug _unifi_core_config "$_unifi_core_config"
    if [ ! -w "$_unifi_core_config" ]; then
      _err "The directory $_unifi_core_config is not writable; please check permissions."
      return 1
    fi

    cat "$_cfullchain" >"${_unifi_core_config}/unifi-core.crt"
    cat "$_ckey" >"${_unifi_core_config}/unifi-core.key"

    if systemctl -q is-active unifi-core; then
      _reload_cmd="${_reload_cmd:+$_reload_cmd && }systemctl restart unifi-core"
    fi
    _info "Install UnifiOS certificate success!"
    _services_updated="${_services_updated} unifi-core"
  elif [ "$DEPLOY_UNIFI_CORE_CONFIG" ]; then
    _err "The specified DEPLOY_UNIFI_CORE_CONFIG='$DEPLOY_UNIFI_CORE_CONFIG' is not valid, please check."
    return 1
  fi

  if [ -z "$_services_updated" ]; then
    # None of the Unifi environments were auto-detected, so no deployment has occurred
    # (and none of DEPLOY_UNIFI_{KEYSTORE,CLOUDKEY_CERTDIR,CORE_CONFIG} were set).
    _err "Unable to detect Unifi environment in standard location."
    _err "(This deploy hook must be run on the Unifi device, not a remote machine.)"
    _err "For non-standard Unifi installations, set DEPLOY_UNIFI_KEYSTORE,"
    _err "DEPLOY_UNIFI_CLOUDKEY_CERTDIR, and/or DEPLOY_UNIFI_CORE_CONFIG as appropriate."
    return 1
  fi

  _reload_cmd="${DEPLOY_UNIFI_RELOAD:-$_reload_cmd}"
  if [ -z "$_reload_cmd" ]; then
    _err "Certificates were installed for services:${_services_updated},"
    _err "but none appear to be active. Please set DEPLOY_UNIFI_RELOAD"
    _err "to a command that will restart the necessary services."
    return 1
  fi
  _info "Reload services (this may take some time): $_reload_cmd"
  if eval "$_reload_cmd"; then
    _info "Reload success!"
  else
    _err "Reload error"
    return 1
  fi

  # Successful, so save all (non-default) config:
  _savedeployconf DEPLOY_UNIFI_KEYSTORE "$DEPLOY_UNIFI_KEYSTORE"
  _savedeployconf DEPLOY_UNIFI_KEYPASS "$DEPLOY_UNIFI_KEYPASS"
  _savedeployconf DEPLOY_UNIFI_CLOUDKEY_CERTDIR "$DEPLOY_UNIFI_CLOUDKEY_CERTDIR"
  _savedeployconf DEPLOY_UNIFI_CORE_CONFIG "$DEPLOY_UNIFI_CORE_CONFIG"
  _savedeployconf DEPLOY_UNIFI_RELOAD "$DEPLOY_UNIFI_RELOAD"

  return 0
}
