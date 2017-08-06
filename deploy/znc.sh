#!/usr/bin/env sh

# Deploy Let's Encrypt certs to ZNC
#
# Any non-zero returns means something wrong has occurred
#
# If you want to use a custom directory and/or user and group owners, you may set the following variables:
#
#   $ZNC_DIR_OWNERSHIP - user and group owners for a directory (e.g. export ZNC_DIR_OWNERSHIP="user:group")
#   $ZNC_DIR - ZNC config directory (e.g. export ZNC_DIR="/home/znc/.znc"), more info (check Misc):
#                       https://wiki.znc.in/Configuration#File_locations

_ZNC_DIR="/var/lib/znc/.znc"
_ZNC_DIR_OWNERSHIP="znc:znc"

########  Public functions #####################

#domain keyfile certfile cafile fullchain
znc_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  # shellcheck disable=SC2034
  _cfullchain="$5"

  # Workaround for SC2153. Check if ZNC_DIR_OWNERSHIP is set to zero,
  # then fallback to _ZNC_DIR_OWNERSHIP.
  if [ -z "$ZNC_DIR_OWNERSHIP" ]; then
    ZNC_DIR_OWNERSHIP="$_ZNC_DIR_OWNERSHIP"
  fi

  # Allow users to override the default ownership for the ZNC config directory
  if [ -n "$ZNC_DIR_OWNERSHIP" ]; then
    _ZNC_DIR_OWNERSHIP="$ZNC_DIR_OWNERSHIP"
    _info "ZNC config directory ownership set to: $_ZNC_DIR_OWNERSHIP"
  fi

  # Retrieve the owner user from a "user:group" string
  # shellcheck disable=SC2034
  _ZNC_USER="$(_getfield "$_ZNC_DIR_OWNERSHIP" 1 ":")"
  if [ $? != 0 ] || [ -z "$_ZNC_USER" ]; then
    _err "Error trying to parse user from ownership string."
    return $?
  fi

  # Retrieve the directory owner group from a "user:group" string
  # shellcheck disable=SC2034
  _ZNC_GROUP="$(_getfield "$_ZNC_DIR_OWNERSHIP" 2 ":")"
  if [ $? != 0 ] || [ -z "$_ZNC_GROUP" ]; then
    _err "Error trying to parse group from ownership string."
    return $?
  fi

  # Workaround for SC2153. Check if ZNC_DIR is set to zero,
  # then fallback to _ZNC_DIR.
  if [ -z "$ZNC_DIR" ]; then
    ZNC_DIR="$_ZNC_DIR"
  fi

  # Allow users to override the default ZNC config directory
  if [ -n "$ZNC_DIR" ]; then
    _ZNC_DIR="$ZNC_DIR"
    _info "ZNC config path set to: $_ZNC_DIR"
  fi

  # Check if the current user is not root before proceeding.
  _curr_user="$(id -u)"
  if [ "$_curr_user" != "0" ]; then
    # Check if acme.sh is running as the owner of the ZNC config directory
    # This is required to not use chown and change the certificates permissions
    _curr_user="$(id -u -n)"
    if [ "$_curr_user" != "$_ZNC_USER" ]; then
      _err "acme.sh must be run by the ZNC user."
      _err "Please run acme.sh as '$_ZNC_USER'."
      return 1
    fi

    # Check if the current user is a member of the owner group of the config directory
    # This is required to not use chown and change the certificates permissions
    # shellcheck disable=SC2034
    if ! id -Gn "$_curr_user" | grep -cw "$_ZNC_GROUP"; then
      _err "The current user is not a member of the '$_ZNC_GROUP' group."
      return 2
    fi

    # Check if we can get the owners of the specified config directory
    _dir_ownership="$(_stat "$_ZNC_DIR")"
    if [ $? != 0 ]; then
      _err "Error getting ownership of $_ZNC_DIR"
      return 3
    fi

    # Check if the specified config directory is owned by the specified user and the specified group
    if [ "$_dir_ownership" != "$_ZNC_DIR_OWNERSHIP" ]; then
      _err "The specified ZNC config directory isn't owned by user '$_ZNC_USER' and group '$_ZNC_GROUP'."
      _err "Please specify the correct directory or correct directory ownership."
      return 4
    fi
  fi

  # Save ZNC user and config directory to domain.conf
  _savedomainconf ZNC_DIR "$_ZNC_DIR"
  _savedomainconf ZNC_DIR_OWNERSHIP "$_ZNC_DIR_OWNERSHIP"

  # ZNC certificate file location
  _znc_cert="$_ZNC_DIR/znc.pem"

  # Please read https://wiki.znc.in/Signed_SSL_certificate
  _info "Generating ZNC certificate file for $_cdomain"

  cat "$_ckey" >"$_znc_cert"
  if [ $? != 0 ]; then
    _err "Error generating ZNC certificate file (private key error)."
    return 5
  fi

  cat "$_ccert" >>"$_znc_cert"
  if [ $? != 0 ]; then
    _err "Error generating ZNC certificate file (certificate error)."
    return 6
  fi

  cat "$_cca" >>"$_znc_cert"
  if [ $? != 0 ]; then
    _err "Error generating ZNC certificate file (CA certificate error)."
    return 7
  fi

  # If running as root, check if certificate file owner is ZNC
  _cert_ownership="$(_stat "$_znc_cert")"
  if [ $? != 0 ]; then
    _err "Error getting ownership of: $_znc_cert"
    return 8
  fi

  # Check if the certificate is owned by the ZNC user and group.
  # If not, fix it.
  if [ "$_cert_ownership" != "$_ZNC_DIR_OWNERSHIP" ]; then
    chown $_ZNC_DIR_OWNERSHIP $_znc_cert
    if [ $? != 0 ]; then
      _err "Error changing ownership of: $_znc_cert"
      return 9
    fi

    _info "Changed ownership of '$_znc_cert' to '$_ZNC_DIR_OWNERSHIP'"
  fi

  _info "Successfully generated ZNC certificate file at: $_znc_cert"
  return 0
}
