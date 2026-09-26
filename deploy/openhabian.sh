#!/usr/bin/env sh

# Deploy script to install keys to the openHAB keystore

# This script attempts to restart the openHAB service upon completion.
# In order for this to work, the user running acme.sh needs to be able
# to execute the DEPLOY_OPENHABIAN_RESTART command
# (default: sudo service openhab restart) without needing a password prompt.
# To ensure this deployment runs properly ensure permissions are configured
# correctly, or change the command variable as needed.

# Configuration options:
# DEPLOY_OPENHABIAN_KEYPASS :  The default should be appropriate here for most cases,
#                              but change this to change the password used for the keystore.
# DEPLOY_OPENHABIAN_KEYSTORE : The full path of the openHAB keystore file. This will
#                              default to a path based on the $OPENHAB_USERDATA directory.
#                              This should generate based on existing openHAB env vars.
# DEPLOY_OPENHABIAN_RESTART :  The command used to restart openHAB

openhabian_deploy() {

    # Name parameters, load configs
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

    _getdeployconf DEPLOY_OPENHABIAN_KEYSTORE
    _getdeployconf DEPLOY_OPENHABIAN_KEYPASS
    _getdeployconf DEPLOY_OPENHABIAN_RESTART

    _debug2 DEPLOY_OPENHABIAN_KEYSTORE "$DEPLOY_OPENHABIAN_KEYSTORE"
    _debug2 DEPLOY_OPENHABIAN_KEYPASS "$DEPLOY_OPENHABIAN_KEYPASS"
    _debug2 DEPLOY_OPENHABIAN_RESTART "$DEPLOY_OPENHABIAN_RESTART"

    # Define configurable options
    _openhab_keystore="${DEPLOY_OPENHABIAN_KEYSTORE:-${OPENHAB_USERDATA}/etc/keystore}"
    _openhab_keypass="${DEPLOY_OPENHABIAN_KEYPASS:-openhab}"
    _default_restart="sudo service openhab restart"
    _openhab_restart="${DEPLOY_OPENHABIAN_RESTART:-$_default_restart}"

    _debug _openhab_keystore "$_openhab_keystore"
    _debug _openhab_keypass "$_openhab_keypass"
    _debug _openhab_restart "$_openhab_restart"

    # Verify Dependencies
    if ! _exists keytool; then
        _err "keytool not found, please install keytool"
        return 1
    fi
    if [ ! -w "$_openhab_keystore" ]; then
        _err "The file $_openhab_keystore is not writable, please change the permission."
        return 1
    fi

    # Take a backup of the old keystore
    _debug "Storing a backup of the existing keystore at ${_openhab_keystore}.bak"
    cp "${_openhab_keystore}" "${_openhab_keystore}.bak"

    # Generate PKCS12 keystore
    _new_pkcs12="$(_mktemp)"
    # _toPkcs doesn't support -nodes param
    if ${ACME_OPENSSL_BIN:-openssl} pkcs12 \
        -export \
        -inkey "$_ckey" \
        -in "$_ccert" \
        -certfile "$_cca" \
        -name mykey \
        -out "$_new_pkcs12" \
        -nodes -passout "pass:$_openhab_keypass"; then
        _debug "Successfully created pkcs keystore"
    else
        _err "Error generating pkcs12."
        _err "Please re-run with --debug and report a bug."
        rm "$_new_pkcs12"
        return 1
    fi

    # Remove old cert from existing store
    if keytool -delete \
        -alias mykey \
        -deststorepass "$_openhab_keypass" \
        -keystore "$_openhab_keystore"; then
        _info "Successfully deleted old key"
    else
        _err "Error deleting old key"
        _err "Please re-run with --debug and report a bug."
        rm "$_new_pkcs12"
        return 1
    fi

    # Add new certificate to store
    if keytool -importkeystore \
        -srckeystore "$_new_pkcs12" \
        -srcstoretype PKCS12 \
        -srcstorepass "$_openhab_keypass" \
        -alias mykey \
        -destkeystore "$_openhab_keystore" \
        -deststoretype jks \
        -deststorepass "$_openhab_keypass" \
        -destalias mykey; then
        _info "Successfully imported new key"
    else
        _err "Failure when importing key"
        _err "Please re-run with --debug and report a bug."
        rm "$_new_pkcs12"
        return 1
    fi

    # Reload openHAB service
    if eval "$_openhab_restart"; then
        _info "Restarted openhab"
    else
        _err "Failed to restart openHAB, please restart openHAB manually."
        _err "The new key has been installed, but openHAB may not use it until restarted"
        _err "To prevent this error, override the restart command with DEPLOY_OPENHABIAN_RESTART \
            and ensure it can be called by the acme.sh user"
        return 1
    fi

    _savedeployconf DEPLOY_OPENHABIAN_KEYSTORE "$DEPLOY_OPENHABIAN_KEYSTORE"
    _savedeployconf DEPLOY_OPENHABIAN_KEYPASS "$DEPLOY_OPENHABIAN_KEYPASS"
    _savedeployconf DEPLOY_OPENHABIAN_RESTART "$DEPLOY_OPENHABIAN_RESTART"

    rm "$_new_pkcs12"
}

# Credits:
# This solution was heavily informed by a few existing scripts:
# - https://gist.github.com/jpmens/8029383
# - https://github.com/matsahm/openhab_change_ssl/blob/bd46986581631319606ae4c594d4ed774a67cd39/openhab_change_ssl
# Thank you!
