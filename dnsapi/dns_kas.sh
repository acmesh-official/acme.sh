#!/usr/bin/env sh
########################################################################
# All-inkl Kasserver hook script for acme.sh
#
# Environment variables:
#
#  - $KAS_Login (Kasserver API login name)
#  - $KAS_Authtype (Kasserver API auth type. Default: sha1)
#  - $KAS_Authdata (Kasserver API auth data.)
#
# Author: Martin Kammerlander, Phlegx Systems OG <martin.kammerlander@phlegx.com>
# Credits: Inspired by dns_he.sh. Thanks a lot man!
# Git repo: https://github.com/phlegx/acme.sh
# TODO: Better Error handling
# TODO: Does not work with Domains that have double endings like i.e. 'co.uk'
#       => Get all root zones and compare once the provider offers that.

KAS_Api="https://kasapi.kasserver.com/dokumentation/formular.php"

########  Public functions #####################

dns_kas_add() {
  _fulldomain=$1
  _txtvalue=$2
  _info "Using DNS-01 All-inkl/Kasserver hook"
  _info "Adding or Updating $_fulldomain DNS TXT entry on All-inkl/Kasserver"

  _check_and_save
  _get_zone "$_fulldomain"
  _get_record_name "$_fulldomain"
  _get_record_id

  _info "Creating TXT DNS record"
  params="?kas_login=$KAS_Login"
  params="$params&kas_auth_type=$KAS_Authtype"
  params="$params&kas_auth_data=$KAS_Authdata"
  params="$params&var1=record_name"
  params="$params&wert1=$_record_name"
  params="$params&var2=record_type"
  params="$params&wert2=TXT"
  params="$params&var3=record_data"
  params="$params&wert3=$_txtvalue"
  params="$params&var4=record_aux"
  params="$params&wert4=0"
  params="$params&kas_action=add_dns_settings"
  params="$params&var5=zone_host"
  params="$params&wert5=$_zone"

  response="$(_get "$KAS_Api$params")"
  _debug2 "response" "$response"

  if ! _contains "$response" "TRUE"; then
    _err "An unkown error occurred, please check manually."
    return 1
  fi
  return 0
}

dns_kas_rm() {
  _fulldomain=$1
  _txtvalue=$2
  _info "Using DNS-01 All-inkl/Kasserver hook"
  _info "Cleaning up after All-inkl/Kasserver hook"
  _info "Removing $_fulldomain DNS TXT entry on All-inkl/Kasserver"

  _check_and_save
  _get_zone "$_fulldomain"
  _get_record_name "$_fulldomain"
  _get_record_id

  # If there is a record_id, delete the entry
  if [ -n "$_record_id" ]; then
    params="?kas_login=$KAS_Login"
    params="$params&kas_auth_type=$KAS_Authtype"
    params="$params&kas_auth_data=$KAS_Authdata"
    params="$params&kas_action=delete_dns_settings"
    params="$params&var1=record_id"
    params="$params&wert1=$_record_id"
    response="$(_get "$KAS_Api$params")"
    _debug2 "response" "$response"
    if ! _contains "$response" "TRUE"; then
      _err "Either the txt record is not found or another error occurred, please check manually."
      return 1
    fi
  else # Cannot delete or unkown error
    _err "No record_id found that can be deleted. Please check manually."
    return 1
  fi
 return 0
}

########################## PRIVATE FUNCTIONS ###########################

# Checks for the ENV variables and saves them
_check_and_save() {
  KAS_Login="${KAS_Login:-$(_readaccountconf_mutable KAS_Login)}"
  KAS_Authtype="${KAS_Authtype:-$(_readaccountconf_mutable KAS_Authtype)}"
  KAS_Authdata="${KAS_Authdata:-$(_readaccountconf_mutable KAS_Authdata)}"

  if [ -z "$KAS_Login" ] || [ -z "$KAS_Authtype" ] || [ -z "$KAS_Authdata" ]; then
    KAS_Login=
    KAS_Authtype=
    KAS_Authdata=
    _err "No auth details provided. Please set user credentials using the \$KAS_Login, \$KAS_Authtype, and \$KAS_Authdata environment variables."
    return 1
  fi
  _saveaccountconf_mutable KAS_Login "$KAS_Login"
  _saveaccountconf_mutable KAS_Authtype "$KAS_Authtype"
  _saveaccountconf_mutable KAS_Authdata "$KAS_Authdata"
  return 0
}

# Gets back the base domain/zone.
# TODO Get a list of all possible root zones and compare (Currently not possible via provider)
# See: https://github.com/Neilpang/acme.sh/wiki/DNS-API-Dev-Guide
_get_zone() {
  _zone=$(echo "$1" | rev | cut -d . -f1-2 | rev).
  return 0
}

# Removes the domain/subdomain from the entry since kasserver
# cannot handle _fulldomain
# TODO Get a list of all possible root zones and compare (Currently not possible via provider)
# See: https://github.com/Neilpang/acme.sh/wiki/DNS-API-Dev-Guide
_get_record_name() {
  _record_name=$(echo "$1" | rev | cut -d"." -f3- | rev)
  return 0
}

# Retrieve the DNS record ID
_get_record_id() {
  params="?kas_login=$KAS_Login"
  params="$params&kas_auth_type=$KAS_Authtype"
  params="$params&kas_auth_data=$KAS_Authdata"
  params="$params&kas_action=get_dns_settings"
  params="$params&var1=zone_host"
  params="$params&wert1=$_zone"

  response="$(_get "$KAS_Api$params")"
  _debug2 "response" "$response"

  _record_id="$(echo "$response" | grep -A 4  "$_record_name" | grep "record_id" | cut -f2 -d">" | xargs)"
  echo "###########################"
  echo "$_record_name"
  echo "$_record_id"
  echo "###########################"
  echo "$response"
  echo "###########################"
  _debug2 _record_id "$_record_id"
  return 0
}
