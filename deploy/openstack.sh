#!/usr/bin/env sh

# OpenStack Barbican deploy hook
#
# This requires you to have OpenStackClient and python-barbicanclient
# installed.
#
# You will require Keystone V3 credentials loaded into your environment, which
# could be either password or v3applicationcredential type.
#
# Author: Andy Botting <andy@andybotting.com>

openstack_deploy() {
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

  if ! _exists openstack; then
    _err "OpenStack client not found"
    return 1
  fi

  _openstack_credentials || return $?

  _info "Generate import pkcs12"
  _import_pkcs12="$(_mktemp)"
  if ! _openstack_to_pkcs "$_import_pkcs12" "$_ckey" "$_ccert" "$_cca"; then
    _err "Error creating pkcs12 certificate"
    return 1
  fi
  _debug _import_pkcs12 "$_import_pkcs12"
  _base64_pkcs12=$(_base64 "multiline" <"$_import_pkcs12")

  secretHrefs=$(_openstack_get_secrets)
  _debug secretHrefs "$secretHrefs"
  _openstack_store_secret || return $?

  if [ -n "$secretHrefs" ]; then
    _info "Cleaning up existing secret"
    _openstack_delete_secrets || return $?
  fi

  _info "Certificate successfully deployed"
  return 0
}

_openstack_store_secret() {
  if ! openstack secret store --name "$_cdomain." -t 'application/octet-stream' -e base64 --payload "$_base64_pkcs12"; then
    _err "Failed to create OpenStack secret"
    return 1
  fi
  return
}

_openstack_delete_secrets() {
  echo "$secretHrefs" | while read -r secretHref; do
    _info "Deleting old secret $secretHref"
    if ! openstack secret delete "$secretHref"; then
      _err "Failed to delete OpenStack secret"
      return 1
    fi
  done
  return
}

_openstack_get_secrets() {
  if ! secretHrefs=$(openstack secret list -f value --name "$_cdomain." | cut -d' ' -f1); then
    _err "Failed to list secrets"
    return 1
  fi
  echo "$secretHrefs"
}

_openstack_to_pkcs() {
  # The existing _toPkcs command can't allow an empty password, due to sh
  # -z test, so copied here and forcing the empty password.
  _cpfx="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"

  ${ACME_OPENSSL_BIN:-openssl} pkcs12 -export -out "$_cpfx" -inkey "$_ckey" -in "$_ccert" -certfile "$_cca" -password "pass:"
}

_openstack_credentials() {
  _debug "Check OpenStack credentials"

  # If we have OS_AUTH_URL already set in the environment, then assume we want
  # to use those, otherwise use stored credentials
  if [ -n "$OS_AUTH_URL" ]; then
    _debug "OS_AUTH_URL env var found, using environment"
  else
    _debug "OS_AUTH_URL not found, loading stored credentials"
    OS_AUTH_URL="${OS_AUTH_URL:-$(_readaccountconf_mutable OS_AUTH_URL)}"
    OS_IDENTITY_API_VERSION="${OS_IDENTITY_API_VERSION:-$(_readaccountconf_mutable OS_IDENTITY_API_VERSION)}"
    OS_AUTH_TYPE="${OS_AUTH_TYPE:-$(_readaccountconf_mutable OS_AUTH_TYPE)}"
    OS_APPLICATION_CREDENTIAL_ID="${OS_APPLICATION_CREDENTIAL_ID:-$(_readaccountconf_mutable OS_APPLICATION_CREDENTIAL_ID)}"
    OS_APPLICATION_CREDENTIAL_SECRET="${OS_APPLICATION_CREDENTIAL_SECRET:-$(_readaccountconf_mutable OS_APPLICATION_CREDENTIAL_SECRET)}"
    OS_USERNAME="${OS_USERNAME:-$(_readaccountconf_mutable OS_USERNAME)}"
    OS_PASSWORD="${OS_PASSWORD:-$(_readaccountconf_mutable OS_PASSWORD)}"
    OS_PROJECT_NAME="${OS_PROJECT_NAME:-$(_readaccountconf_mutable OS_PROJECT_NAME)}"
    OS_PROJECT_ID="${OS_PROJECT_ID:-$(_readaccountconf_mutable OS_PROJECT_ID)}"
    OS_USER_DOMAIN_NAME="${OS_USER_DOMAIN_NAME:-$(_readaccountconf_mutable OS_USER_DOMAIN_NAME)}"
    OS_USER_DOMAIN_ID="${OS_USER_DOMAIN_ID:-$(_readaccountconf_mutable OS_USER_DOMAIN_ID)}"
    OS_PROJECT_DOMAIN_NAME="${OS_PROJECT_DOMAIN_NAME:-$(_readaccountconf_mutable OS_PROJECT_DOMAIN_NAME)}"
    OS_PROJECT_DOMAIN_ID="${OS_PROJECT_DOMAIN_ID:-$(_readaccountconf_mutable OS_PROJECT_DOMAIN_ID)}"
  fi

  # Check each var and either save or clear it depending on whether its set.
  # The helps us clear out old vars in the case where a user may want
  # to switch between password and app creds
  _debug "OS_AUTH_URL" "$OS_AUTH_URL"
  if [ -n "$OS_AUTH_URL" ]; then
    export OS_AUTH_URL
    _saveaccountconf_mutable OS_AUTH_URL "$OS_AUTH_URL"
  else
    unset OS_AUTH_URL
    _clearaccountconf SAVED_OS_AUTH_URL
  fi

  _debug "OS_IDENTITY_API_VERSION" "$OS_IDENTITY_API_VERSION"
  if [ -n "$OS_IDENTITY_API_VERSION" ]; then
    export OS_IDENTITY_API_VERSION
    _saveaccountconf_mutable OS_IDENTITY_API_VERSION "$OS_IDENTITY_API_VERSION"
  else
    unset OS_IDENTITY_API_VERSION
    _clearaccountconf SAVED_OS_IDENTITY_API_VERSION
  fi

  _debug "OS_AUTH_TYPE" "$OS_AUTH_TYPE"
  if [ -n "$OS_AUTH_TYPE" ]; then
    export OS_AUTH_TYPE
    _saveaccountconf_mutable OS_AUTH_TYPE "$OS_AUTH_TYPE"
  else
    unset OS_AUTH_TYPE
    _clearaccountconf SAVED_OS_AUTH_TYPE
  fi

  _debug "OS_APPLICATION_CREDENTIAL_ID" "$OS_APPLICATION_CREDENTIAL_ID"
  if [ -n "$OS_APPLICATION_CREDENTIAL_ID" ]; then
    export OS_APPLICATION_CREDENTIAL_ID
    _saveaccountconf_mutable OS_APPLICATION_CREDENTIAL_ID "$OS_APPLICATION_CREDENTIAL_ID"
  else
    unset OS_APPLICATION_CREDENTIAL_ID
    _clearaccountconf SAVED_OS_APPLICATION_CREDENTIAL_ID
  fi

  _secure_debug "OS_APPLICATION_CREDENTIAL_SECRET" "$OS_APPLICATION_CREDENTIAL_SECRET"
  if [ -n "$OS_APPLICATION_CREDENTIAL_SECRET" ]; then
    export OS_APPLICATION_CREDENTIAL_SECRET
    _saveaccountconf_mutable OS_APPLICATION_CREDENTIAL_SECRET "$OS_APPLICATION_CREDENTIAL_SECRET"
  else
    unset OS_APPLICATION_CREDENTIAL_SECRET
    _clearaccountconf SAVED_OS_APPLICATION_CREDENTIAL_SECRET
  fi

  _debug "OS_USERNAME" "$OS_USERNAME"
  if [ -n "$OS_USERNAME" ]; then
    export OS_USERNAME
    _saveaccountconf_mutable OS_USERNAME "$OS_USERNAME"
  else
    unset OS_USERNAME
    _clearaccountconf SAVED_OS_USERNAME
  fi

  _secure_debug "OS_PASSWORD" "$OS_PASSWORD"
  if [ -n "$OS_PASSWORD" ]; then
    export OS_PASSWORD
    _saveaccountconf_mutable OS_PASSWORD "$OS_PASSWORD"
  else
    unset OS_PASSWORD
    _clearaccountconf SAVED_OS_PASSWORD
  fi

  _debug "OS_PROJECT_NAME" "$OS_PROJECT_NAME"
  if [ -n "$OS_PROJECT_NAME" ]; then
    export OS_PROJECT_NAME
    _saveaccountconf_mutable OS_PROJECT_NAME "$OS_PROJECT_NAME"
  else
    unset OS_PROJECT_NAME
    _clearaccountconf SAVED_OS_PROJECT_NAME
  fi

  _debug "OS_PROJECT_ID" "$OS_PROJECT_ID"
  if [ -n "$OS_PROJECT_ID" ]; then
    export OS_PROJECT_ID
    _saveaccountconf_mutable OS_PROJECT_ID "$OS_PROJECT_ID"
  else
    unset OS_PROJECT_ID
    _clearaccountconf SAVED_OS_PROJECT_ID
  fi

  _debug "OS_USER_DOMAIN_NAME" "$OS_USER_DOMAIN_NAME"
  if [ -n "$OS_USER_DOMAIN_NAME" ]; then
    export OS_USER_DOMAIN_NAME
    _saveaccountconf_mutable OS_USER_DOMAIN_NAME "$OS_USER_DOMAIN_NAME"
  else
    unset OS_USER_DOMAIN_NAME
    _clearaccountconf SAVED_OS_USER_DOMAIN_NAME
  fi

  _debug "OS_USER_DOMAIN_ID" "$OS_USER_DOMAIN_ID"
  if [ -n "$OS_USER_DOMAIN_ID" ]; then
    export OS_USER_DOMAIN_ID
    _saveaccountconf_mutable OS_USER_DOMAIN_ID "$OS_USER_DOMAIN_ID"
  else
    unset OS_USER_DOMAIN_ID
    _clearaccountconf SAVED_OS_USER_DOMAIN_ID
  fi

  _debug "OS_PROJECT_DOMAIN_NAME" "$OS_PROJECT_DOMAIN_NAME"
  if [ -n "$OS_PROJECT_DOMAIN_NAME" ]; then
    export OS_PROJECT_DOMAIN_NAME
    _saveaccountconf_mutable OS_PROJECT_DOMAIN_NAME "$OS_PROJECT_DOMAIN_NAME"
  else
    unset OS_PROJECT_DOMAIN_NAME
    _clearaccountconf SAVED_OS_PROJECT_DOMAIN_NAME
  fi

  _debug "OS_PROJECT_DOMAIN_ID" "$OS_PROJECT_DOMAIN_ID"
  if [ -n "$OS_PROJECT_DOMAIN_ID" ]; then
    export OS_PROJECT_DOMAIN_ID
    _saveaccountconf_mutable OS_PROJECT_DOMAIN_ID "$OS_PROJECT_DOMAIN_ID"
  else
    unset OS_PROJECT_DOMAIN_ID
    _clearaccountconf SAVED_OS_PROJECT_DOMAIN_ID
  fi

  if [ "$OS_AUTH_TYPE" = "v3applicationcredential" ]; then
    # Application Credential auth
    if [ -z "$OS_APPLICATION_CREDENTIAL_ID" ] || [ -z "$OS_APPLICATION_CREDENTIAL_SECRET" ]; then
      _err "When using OpenStack application credentials, OS_APPLICATION_CREDENTIAL_ID"
      _err "and OS_APPLICATION_CREDENTIAL_SECRET must be set."
      _err "Please check your credentials and try again."
      return 1
    fi
  else
    # Password auth
    if [ -z "$OS_USERNAME" ] || [ -z "$OS_PASSWORD" ]; then
      _err "OpenStack username or password not found."
      _err "Please check your credentials and try again."
      return 1
    fi

    if [ -z "$OS_PROJECT_NAME" ] && [ -z "$OS_PROJECT_ID" ]; then
      _err "When using password authentication, OS_PROJECT_NAME or"
      _err "OS_PROJECT_ID must be set."
      _err "Please check your credentials and try again."
      return 1
    fi
  fi

  return 0
}
