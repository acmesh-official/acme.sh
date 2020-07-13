#!/usr/bin/env sh

# OpenStack Designate API plugin
#
# This requires you to have OpenStackClient and python-desginateclient
# installed.
#
# You will require Keystone V3 credentials loaded into your environment, which
# could be either password or v3applicationcredential type.
#
# Author: Andy Botting <andy@andybotting.com>

########  Public functions #####################

# Usage: dns_openstack_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_openstack_add() {
  fulldomain=$1
  txtvalue=$2
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  _dns_openstack_credentials || return $?
  _dns_openstack_check_setup || return $?
  _dns_openstack_find_zone || return $?
  _dns_openstack_get_recordset || return $?
  _debug _recordset_id "$_recordset_id"
  if [ -n "$_recordset_id" ]; then
    _dns_openstack_get_records || return $?
    _debug _records "$_records"
  fi
  _dns_openstack_create_recordset || return $?
}

# Usage: dns_openstack_rm   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
# Remove the txt record after validation.
dns_openstack_rm() {
  fulldomain=$1
  txtvalue=$2
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  _dns_openstack_credentials || return $?
  _dns_openstack_check_setup || return $?
  _dns_openstack_find_zone || return $?
  _dns_openstack_get_recordset || return $?
  _debug _recordset_id "$_recordset_id"
  if [ -n "$_recordset_id" ]; then
    _dns_openstack_get_records || return $?
    _debug _records "$_records"
  fi
  _dns_openstack_delete_recordset || return $?
}

####################  Private functions below ##################################

_dns_openstack_create_recordset() {

  if [ -z "$_recordset_id" ]; then
    _info "Creating a new recordset"
    if ! _recordset_id=$(openstack recordset create -c id -f value --type TXT --record "$txtvalue" "$_zone_id" "$fulldomain."); then
      _err "No recordset ID found after create"
      return 1
    fi
  else
    _info "Updating existing recordset"
    # Build new list of --record <rec> args for update
    _record_args="--record $txtvalue"
    for _rec in $_records; do
      _record_args="$_record_args --record $_rec"
    done
    # shellcheck disable=SC2086
    if ! _recordset_id=$(openstack recordset set -c id -f value $_record_args "$_zone_id" "$fulldomain."); then
      _err "Recordset update failed"
      return 1
    fi
  fi

  _max_retries=60
  _sleep_sec=5
  _retry_times=0
  while [ "$_retry_times" -lt "$_max_retries" ]; do
    _retry_times=$(_math "$_retry_times" + 1)
    _debug3 _retry_times "$_retry_times"

    _record_status=$(openstack recordset show -c status -f value "$_zone_id" "$_recordset_id")
    _info "Recordset status is $_record_status"
    if [ "$_record_status" = "ACTIVE" ]; then
      return 0
    elif [ "$_record_status" = "ERROR" ]; then
      return 1
    else
      _sleep $_sleep_sec
    fi
  done

  _err "Recordset failed to become ACTIVE"
  return 1
}

_dns_openstack_delete_recordset() {

  if [ "$_records" = "$txtvalue" ]; then
    _info "Only one record found, deleting recordset"
    if ! openstack recordset delete "$_zone_id" "$fulldomain." >/dev/null; then
      _err "Failed to delete recordset"
      return 1
    fi
  else
    _info "Found existing records, updating recordset"
    # Build new list of --record <rec> args for update
    _record_args=""
    for _rec in $_records; do
      if [ "$_rec" = "$txtvalue" ]; then
        continue
      fi
      _record_args="$_record_args --record $_rec"
    done
    # shellcheck disable=SC2086
    if ! openstack recordset set -c id -f value $_record_args "$_zone_id" "$fulldomain." >/dev/null; then
      _err "Recordset update failed"
      return 1
    fi
  fi
}

_dns_openstack_get_root() {
  # Take the full fqdn and strip away pieces until we get an exact zone name
  # match. For example, _acme-challenge.something.domain.com might need to go
  # into something.domain.com or domain.com
  _zone_name=$1
  _zone_list=$2
  while [ "$_zone_name" != "" ]; do
    _zone_name="$(echo "$_zone_name" | sed 's/[^.]*\.*//')"
    echo "$_zone_list" | while read -r id name; do
      if _startswith "$_zone_name." "$name"; then
        echo "$id"
      fi
    done
  done | _head_n 1
}

_dns_openstack_find_zone() {
  if ! _zone_list="$(openstack zone list -c id -c name -f value)"; then
    _err "Can't list zones. Check your OpenStack credentials"
    return 1
  fi
  _debug _zone_list "$_zone_list"

  if ! _zone_id="$(_dns_openstack_get_root "$fulldomain" "$_zone_list")"; then
    _err "Can't find a matching zone. Check your OpenStack credentials"
    return 1
  fi
  _debug _zone_id "$_zone_id"
}

_dns_openstack_get_records() {
  if ! _records=$(openstack recordset show -c records -f value "$_zone_id" "$fulldomain."); then
    _err "Failed to get records"
    return 1
  fi
  return 0
}

_dns_openstack_get_recordset() {
  if ! _recordset_id=$(openstack recordset list -c id -f value --name "$fulldomain." "$_zone_id"); then
    _err "Failed to get recordset"
    return 1
  fi
  return 0
}

_dns_openstack_check_setup() {
  if ! _exists openstack; then
    _err "OpenStack client not found"
    return 1
  fi
}

_dns_openstack_credentials() {
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
