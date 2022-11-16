#!/usr/bin/env sh

# Config variables
# DEPLOY_OPENHABIAN_KEYPASS : This should be default most of the time since a custom password requires openhab config changes
# DEPLOY_OPENHABIAN_KEYSTORE : This should generate based on existing openhab env vars.

openhabian_deploy() {

    # Name parameters
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

    # TODO: Load from config using _getdeployconf and print with _debug2
    # Unclear if this is needed in this case.

    # Define configurable options
    _openhab_keystore=${DEPLOY_OPENHABIAN_KEYSTORE:-${OPENHAB_USERDATA}/etc/keystore}
    _openhab_keypass="${DEPLOY_OPENHABIAN_KEYPASS:-openhab}"

    # Take a backup of the old keystore
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
        _debug "Successfully deleted old key"
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
        _debug "Successfully imported key"
    else
        _err "Failure when importing key"
        _err "Please re-run with --debug and report a bug."
        rm "$_new_pkcs12"
        return 1
    fi

    # TODO: Reload/restart openhab to pick up new key
    # Unifi script passes a reload cmd to handle reloading.
    # Consider also stopping openhab before touching the keystore

    rm "$_new_pkcs12"
}
