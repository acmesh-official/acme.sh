#!/usr/bin/env sh

# Samba AD DC
#
# `samba-tool` binary is necessary.
# On Debian, it can be installed with `apt-get install samba-common-bin`
#
# Then the following environment variable will need to be set:
# SAMBA_HOST="dc1.example.com"
# SAMBA_USER="Administrator"
# SAMBA_PASS="fzaoiv23RGgqg"

# Author: Adnan RIHAN <adnan@rihan.fr>
# Report Bugs here: https://github.com/acmesh-official/acme.sh/issues/4852
#
########  Public functions #####################
#
# Usage: dns_samba_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"

dns_samba_add() {
  _debug 'Checking if `samba-tool` is available'
  if ! _exists samba-tool; then
    _err "samba-tool could not be found. Please install samba-common-bin"
    return 1
  fi

  fulldomain=$1
  txtvalue=$2

  SAMBA_HOST="${SAMBA_HOST:-$(_readaccountconf_mutable SAMBA_HOST)}"
  SAMBA_USER="${SAMBA_USER:-$(_readaccountconf_mutable SAMBA_USER)}"
  SAMBA_PASS="${SAMBA_PASS:-$(_readaccountconf_mutable SAMBA_PASS)}"

  if [ -z "$SAMBA_HOST" ] || [ -z "$SAMBA_USER" ] || [ -z "$SAMBA_PASS" ]; then
    SAMBA_HOST=""
    SAMBA_USER=""
    SAMBA_PASS=""
    _err "You must specify a Samba host, username and password."
    return 1
  fi

  # save the credentials to the account conf file.
  _saveaccountconf_mutable SAMBA_HOST "$SAMBA_HOST"
  _saveaccountconf_mutable SAMBA_USER "$SAMBA_USER"
  _saveaccountconf_mutable SAMBA_PASS "$SAMBA_PASS"

  if ! _get_zone $fulldomain; then
    return 1
  fi

  _debug "Adding \"$_subdomain\" = \"$txtvalue\" to $_zone"
  if ! samba-tool dns add "$SAMBA_HOST" "$_zone" "$_subdomain" TXT "$txtvalue" --username="$SAMBA_USER" --password="$SAMBA_PASS" 2>/dev/null; then
    _err "Couldn't add TXT field"
    return 1
  fi
}

# Usage: fulldomain txtvalue
# Remove the txt record after validation.
dns_samba_rm() {
  _debug 'Checking if `samba-tool` is available'
  if ! _exists samba-tool; then
    _err "samba-tool could not be found. Please install samba-common-bin"
    exit 1
  fi

  fulldomain=$1
  txtvalue=$2

  SAMBA_HOST="${SAMBA_HOST:-$(_readaccountconf_mutable SAMBA_HOST)}"
  SAMBA_USER="${SAMBA_USER:-$(_readaccountconf_mutable SAMBA_USER)}"
  SAMBA_PASS="${SAMBA_PASS:-$(_readaccountconf_mutable SAMBA_PASS)}"

  if [ -z "$SAMBA_HOST" ] || [ -z "$SAMBA_USER" ] || [ -z "$SAMBA_PASS" ]; then
    SAMBA_HOST=""
    SAMBA_USER=""
    SAMBA_PASS=""
    _err "You must specify a Samba host, username and password."
    return 1
  fi

  # save the credentials to the account conf file.
  _saveaccountconf_mutable SAMBA_HOST "$SAMBA_HOST"
  _saveaccountconf_mutable SAMBA_USER "$SAMBA_USER"
  _saveaccountconf_mutable SAMBA_PASS "$SAMBA_PASS"

  if ! _get_zone $fulldomain; then
    return 1
  fi

  _debug "Removing \"$_subdomain\" = \"$txtvalue\" from $_zone"
  if ! samba-tool dns delete "$SAMBA_HOST" "$_zone" "$_subdomain" TXT "$txtvalue" --username="$SAMBA_USER" --password="$SAMBA_PASS" 2>/dev/null; then
    _info "Couldn't remove TXT field, may be non existant. Ignoring error."
  fi
}

####################  Private functions below ##################################

_get_zone() {
  _fulldomain=$1

  _debug 'Retrieving samba zonelist'
  _subdomain=""
  _zone=""
  if ! _zones=$(samba-tool dns zonelist "$SAMBA_HOST" --username="$SAMBA_USER" --password="$SAMBA_PASS" 2>/dev/null | grep pszZoneName | cut -d: -f2 | sed 's/ //g'); then
    _err "Couldn't contact Samba AD DC host"
    return 1
  fi

  _debug 'Loop in zonelist to find the correct zone:'
  for z in $_zones; do
    _debug "  Checking \"$z\" against \"$_fulldomain\""
    if _endswith "$_fulldomain" ".$z"; then
      _debug "    Found! \"$_fulldomain\" ends with \".$z\""
      _zone=$z
      _subdomain=${fulldomain%.$z}
      break
    elif [ "$_fulldomain" = "$z" ]; then
      _debug "    Found! \"$_fulldomain\" == \"$z\""
      _zone=$z
      _subdomain="@"
      break
    fi
  done

  if [ -z "$_zone" ]; then
    _err "Can't find a corresponding zone for this domain"
    return 1
  fi
}