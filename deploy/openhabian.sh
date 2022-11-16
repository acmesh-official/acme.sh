#!/usr/bin/env sh

# Config variables
# DEPLOY_OPENHABIAN_KEYPASS : This should be default most of the time since a custom password requires openhab config changes
# DEPLOY_OPENHABIAN_KEYSTORE : This should generate based on existing openhab env vars.

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

    _getdeployconf DEPLOY_UNIFI_KEYSTORE
    _getdeployconf DEPLOY_OPENHABIAN_KEYPASS
    _getdeployconf DEPLOY_OPENHABIAN_RESTART

    _debug2 DEPLOY_UNIFI_KEYSTORE "$DEPLOY_UNIFI_KEYSTORE"
    _debug2 DEPLOY_OPENHABIAN_KEYPASS "$DEPLOY_OPENHABIAN_KEYPASS"
    _debug2 DEPLOY_OPENHABIAN_RESTART "$DEPLOY_OPENHABIAN_RESTART"

    # Define configurable options
    _openhab_keystore="${DEPLOY_OPENHABIAN_KEYSTORE:-${OPENHAB_USERDATA}/etc/keystore}"
    _openhab_keypass="${DEPLOY_OPENHABIAN_KEYPASS:-openhab}"
    _default_restart="sudo service openhab resart"
    _openhab_restart="${DEPLOY_OPENHABIAN_RESTART:-$_default_restart}"

    _debug _openhab_keystore "$_openhab_keystore"
    _debug _openhab_keypass "$_openhab_keypass"
    _debug _openhab_restart "$_openhab_restart"

    # Take a backup of the old keystore
    _debug "Storing a backup of the existing keystore at ${_openhab_keystore}.bak"
    cp "${_openhab_keystore}" "${_openhab_keystore}.bak"

    # Verify Dependencies/PreReqs
    if ! _exists keytool; then
        _err "keytool not found, please install keytool"
        return 1
    fi
    if [ ! -w "$_openhab_keystore" ]; then
        _err "The file $_openhab_keystore is not writable, please change the permission."
        return 1
    fi

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

    # Remove old cert from existing keychain
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

    # Add new certificate to keychain
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

    # Reload openhab service
    if eval "$_openhab_restart"; then
        _info "Restarted opehnab"
    else
        _err "Failed to restart openhab, please restart openhab manually."
        _err "The new key has been installed, but openhab may not use it until restarted"
        _err "To prevent this error, override the restart command with DEPLOY_OPENHABIAN_RESTART \
            and ensure it can be called by the acme.sh user"
    fi

    _savedeployconf DEPLOY_OPENHABIAN_KEYSTORE "$DEPLOY_OPENHABIAN_KEYSTORE"
    _savedeployconf DEPLOY_OPENHABIAN_KEYPASS "$DEPLOY_OPENHABIAN_KEYPASS"
    _savedeployconf DEPLOY_OPENHABIAN_RESTART "$DEPLOY_OPENHABIAN_RESTART"

    rm "$_new_pkcs12"
}
