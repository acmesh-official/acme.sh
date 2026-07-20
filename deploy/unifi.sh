#!/usr/bin/env sh

# Here is a script to deploy cert on a Unifi Controller or Cloud Key device.
# It supports:
#   - self-hosted Unifi Controller
#   - Unifi Cloud Key (Gen1/2/2+)
#   - Unifi Cloud Key running UnifiOS (v2.0.0+, Gen2/2+ only)
#   - Unifi Dream Machine
#       This has not been tested on other "all-in-one" devices such as
#       UDM Pro or Unifi Express.
#
#       OS Version v2.0.0+
#       Network Application version 7.0.0+
#       OS version ~3.1 removed java and keytool from the UnifiOS.
#       Using PKCS12 format keystore appears to work fine.
#
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
# DEPLOY_UNIFI_RELOAD="systemctl restart unifi"
# System Properties file location for controller
#DEPLOY_UNIFI_SYSTEM_PROPERTIES="/usr/lib/unifi/data/system.properties"
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
# DEPLOY_UNIFI_OS_RELOAD="systemctl restart unifi-core"
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
  _getdeployconf DEPLOY_UNIFI_SYSTEM_PROPERTIES
  _getdeployconf DEPLOY_UNIFI_OS_RELOAD

  _debug2 DEPLOY_UNIFI_KEYSTORE "$DEPLOY_UNIFI_KEYSTORE"
  _debug2 DEPLOY_UNIFI_KEYPASS "$DEPLOY_UNIFI_KEYPASS"
  _debug2 DEPLOY_UNIFI_CLOUDKEY_CERTDIR "$DEPLOY_UNIFI_CLOUDKEY_CERTDIR"
  _debug2 DEPLOY_UNIFI_CORE_CONFIG "$DEPLOY_UNIFI_CORE_CONFIG"
  _debug2 DEPLOY_UNIFI_RELOAD "$DEPLOY_UNIFI_RELOAD"
  _debug2 DEPLOY_UNIFI_OS_RELOAD "$DEPLOY_UNIFI_OS_RELOAD"
  _debug2 DEPLOY_UNIFI_SYSTEM_PROPERTIES "$DEPLOY_UNIFI_SYSTEM_PROPERTIES"

  # Space-separated list of environments detected and installed:
  _services_updated=""

  # Default reload commands accumulated as we auto-detect environments:
  _reload_cmd=""

  # Unifi Controller environment (self hosted or any Cloud Key) --
  # auto-detect by file /usr/lib/unifi/data/keystore
  _unifi_keystore="${DEPLOY_UNIFI_KEYSTORE:-/usr/lib/unifi/data/keystore}"
  if [ -f "$_unifi_keystore" ]; then
    _debug _unifi_keystore "$_unifi_keystore"
    if ! _exists keytool; then
      _do_keytool=0
      _info "Installing certificate for Unifi Controller (PKCS12 keystore)."
    else
      _do_keytool=1
      _info "Installing certificate for Unifi Controller (Java keystore)"
    fi
    if [ ! -w "$_unifi_keystore" ]; then
      _err "The file $_unifi_keystore is not writable, please change the permission."
      return 1
    fi

    _unifi_keypass="${DEPLOY_UNIFI_KEYPASS:-aircontrolenterprise}"

    _debug "Generate import pkcs12"
    _import_pkcs12="$(_mktemp)"
    _debug "_toPkcs $_import_pkcs12 $_ckey $_ccert $_cca $_unifi_keypass unifi root"
    _toPkcs "$_import_pkcs12" "$_ckey" "$_ccert" "$_cca" "$_unifi_keypass" unifi root
    # shellcheck disable=SC2181
    if [ "$?" != "0" ]; then
      _err "Error generating pkcs12. Please re-run with --debug and report a bug."
      return 1
    fi

    # Save the existing keystore in case something goes wrong.
    mv -f "${_unifi_keystore}" "${_unifi_keystore}"_original
    _info "Previous keystore saved to ${_unifi_keystore}_original."

    if [ "$_do_keytool" -eq 1 ]; then
      _debug "Import into keystore: $_unifi_keystore"
      if keytool -importkeystore \
        -deststorepass "$_unifi_keypass" -destkeypass "$_unifi_keypass" -destkeystore "$_unifi_keystore" \
        -srckeystore "$_import_pkcs12" -srcstoretype PKCS12 -srcstorepass "$_unifi_keypass" \
        -alias unifi -noprompt; then
        _debug "Import keystore success!"
      else
        _err "Error importing into Unifi Java keystore."
        _err "Please re-run with --debug and report a bug."
        _info "Restoring original keystore."
        mv -f "${_unifi_keystore}"_original "${_unifi_keystore}"
        rm "$_import_pkcs12"
        return 1
      fi
    else
      _debug "Copying new keystore to $_unifi_keystore"
      cp -f "$_import_pkcs12" "$_unifi_keystore"
    fi

    # correct file ownership according to the directory, the keystore is placed in
    _unifi_keystore_dir=$(dirname "${_unifi_keystore}")
    # shellcheck disable=SC2012
    _unifi_keystore_dir_owner=$(ls -ld "${_unifi_keystore_dir}" | awk '{print $3}')
    # shellcheck disable=SC2012
    _unifi_keystore_owner=$(ls -l "${_unifi_keystore}" | awk '{print $3}')
    if ! [ "${_unifi_keystore_owner}" = "${_unifi_keystore_dir_owner}" ]; then
      _debug "Changing keystore owner to ${_unifi_keystore_dir_owner}"
      chown "$_unifi_keystore_dir_owner" "${_unifi_keystore}" >/dev/null 2>&1 # fail quietly if we're not running as root
    fi

    # Update unifi service for certificate cipher compatibility
    _unifi_system_properties="${DEPLOY_UNIFI_SYSTEM_PROPERTIES:-/usr/lib/unifi/data/system.properties}"
    if ${ACME_OPENSSL_BIN:-openssl} pkcs12 \
      -in "$_import_pkcs12" \
      -password pass:aircontrolenterprise \
      -nokeys | ${ACME_OPENSSL_BIN:-openssl} x509 -text \
      -noout | grep -i "signature" | grep -iq ecdsa >/dev/null 2>&1; then
      if [ -f "$(dirname "${DEPLOY_UNIFI_KEYSTORE}")/system.properties" ]; then
        _unifi_system_properties="$(dirname "${DEPLOY_UNIFI_KEYSTORE}")/system.properties"
      else
        _unifi_system_properties="/usr/lib/unifi/data/system.properties"
      fi
      if [ -f "${_unifi_system_properties}" ]; then
        cp -f "${_unifi_system_properties}" "${_unifi_system_properties}"_original
        _info "Updating system configuration for cipher compatibility."
        _info "Saved original system config to ${_unifi_system_properties}_original"
        sed -i '/unifi\.https\.ciphers/d' "${_unifi_system_properties}"
        echo "unifi.https.ciphers=ECDHE-ECDSA-AES256-GCM-SHA384,ECDHE-RSA-AES128-GCM-SHA256" >>"${_unifi_system_properties}"
        sed -i '/unifi\.https\.sslEnabledProtocols/d' "${_unifi_system_properties}"
        echo "unifi.https.sslEnabledProtocols=TLSv1.3,TLSv1.2" >>"${_unifi_system_properties}"
        _info "System configuration updated."
      fi
    fi

    rm "$_import_pkcs12"

    # Restarting unifi-core will bring up unifi, doing it out of order results in
    # a certificate error, and breaks wifiman.
    # Restart if we aren't doing Unifi OS (e.g. unifi-core service), otherwise stop for later restart.
    _unifi_reload="${DEPLOY_UNIFI_RELOAD:-systemctl restart unifi}"
    if [ ! -f "${DEPLOY_UNIFI_CORE_CONFIG:-/data/unifi-core/config}/unifi-core.key" ]; then
      _reload_cmd="${_reload_cmd:+$_reload_cmd && }$_unifi_reload"
    else
      _info "Stopping Unifi Controller for later restart."
      _unifi_stop=$(echo "${_unifi_reload}" | sed -e 's/restart/stop/')
      $_unifi_stop
      _reload_cmd="${_reload_cmd:+$_reload_cmd && }$_unifi_reload"
      _info "Unifi Controller stopped."
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
    # It appears that unifi won't start if this is a symlink, so we'll copy it instead.

    # if ! cmp -s "$_unifi_keystore" "${_cloudkey_certdir}/unifi.keystore.jks"; then
    #   _err "Unsupported Cloud Key configuration: keystore not found at '${_cloudkey_certdir}/unifi.keystore.jks'"
    #   return 1
    # fi

    _info "Updating ${_cloudkey_certdir}/unifi.keystore.jks"
    if [ -e "${_cloudkey_certdir}/unifi.keystore.jks" ]; then
      if [ -L "${_cloudkey_certdir}/unifi.keystore.jks" ]; then
        rm -f "${_cloudkey_certdir}/unifi.keystore.jks"
      else
        mv "${_cloudkey_certdir}/unifi.keystore.jks" "${_cloudkey_certdir}/unifi.keystore.jks_original"
      fi
    fi

    cp "${_unifi_keystore}" "${_cloudkey_certdir}/unifi.keystore.jks"

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

    # Save the existing certs in case something goes wrong.
    cp -f "${_unifi_core_config}"/unifi-core.crt "${_unifi_core_config}"/unifi-core_original.crt
    cp -f "${_unifi_core_config}"/unifi-core.key "${_unifi_core_config}"/unifi-core_original.key
    _info "Previous certificate and key saved to ${_unifi_core_config}/unifi-core_original.crt.key."

    cat "$_cfullchain" >"${_unifi_core_config}/unifi-core.crt"
    cat "$_ckey" >"${_unifi_core_config}/unifi-core.key"

    _unifi_os_reload="${DEPLOY_UNIFI_OS_RELOAD:-systemctl restart unifi-core}"
    _reload_cmd="${_reload_cmd:+$_reload_cmd && }$_unifi_os_reload"

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
  _savedeployconf DEPLOY_UNIFI_OS_RELOAD "$DEPLOY_UNIFI_OS_RELOAD"
  _savedeployconf DEPLOY_UNIFI_SYSTEM_PROPERTIES "$DEPLOY_UNIFI_SYSTEM_PROPERTIES"

  return 0
}
