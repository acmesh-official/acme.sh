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
########################################################################

KAS_Api="https://kasapi.kasserver.com/dokumentation/formular.php"

########  Public functions #####################

dns_kas_add() {
  _fulldomain=$1
  _txtvalue=$2
  _info "Using DNS-01 All-inkl/Kasserver hook"
  _info "Adding or Updating $_fulldomain DNS TXT entry on All-inkl/Kasserver"

  _check_and_save
  _get_zone_and_record_name "$_fulldomain"
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
  _debug2 "Wait for 10 seconds by default before calling KAS API."
  sleep 10
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
  _get_zone_and_record_name "$_fulldomain"
  _get_record_id

  # If there is a record_id, delete the entry
  if [ -n "$_record_id" ]; then
    params="?kas_login=$KAS_Login"
    params="$params&kas_auth_type=$KAS_Authtype"
    params="$params&kas_auth_data=$KAS_Authdata"
    params="$params&kas_action=delete_dns_settings"

    for i in $_record_id; do
      params2="$params&var1=record_id"
      params2="$params2&wert1=$i"
      _debug2 "Wait for 10 seconds by default before calling KAS API."
      sleep 10
      response="$(_get "$KAS_Api$params2")"
      _debug2 "response" "$response"
      if ! _contains "$response" "TRUE"; then
        _err "Either the txt record is not found or another error occurred, please check manually."
        return 1
      fi
    done
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

# Gets back the base domain/zone and record name.
# See: https://github.com/Neilpang/acme.sh/wiki/DNS-API-Dev-Guide
_get_zone_and_record_name() {
  _zonen="$( echo "$response"  | tr -d "\n\r" | tr -d " " | tr '[]' '<>' | sed "s/=>Array/\n=> Array/g" | tr ' ' '\n' | grep "domain_name" | tr '<' '\n' | grep "domain_name" | cut -d '>' -f 3)"
  _domain="$1"
  if _endswith "$_domain" "."; then
    _domain="$(echo "$_domain" | sed 's/.$//')"
  fi
  _rootzone="$_domain"
  for i in $_zonen; do
    l1=${#_rootzone}
    l2=${#i}
    if _endswith "$_domain" "$i" && [ "$l1" -ge "$l2" ]; then
      _rootzone="$i"
    fi
  done
  _zone="$_rootzone"
  _debug2 "zone:" "$_zone"

  l3=$((${#_domain}-l1-1))
  _record_name="$(echo "$_domain" | cut -c -"$l3")"
  _debug2 "record_name:" "$_record_name"
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

  _debug2 "Wait for 10 seconds by default before calling KAS API."
  sleep 10
  response="$(_get "$KAS_Api$params")"
  _debug2 "response" "$response"
  _record_id="$(echo "$response" | tr -d "\n\r" | tr -d " " | tr '[]' '<>' | sed "s/=>Array/\n=> Array/g" | tr ' ' '\n' | grep "=>$_record_name<" | grep '>TXT<' | tr '<' '\n' | grep record_id | cut -d '>' -f 3)"
  _debug2 _record_id "$_record_id"
  return 0
}
