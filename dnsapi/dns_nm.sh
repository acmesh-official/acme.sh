#!/usr/bin/env sh

########################################################################
# https://namemaster.de hook script for acme.sh
#
# Environment variables:
#
#  - $NM_user      (your namemaster.de API username)
#  - $NM_md5       (your namemaster.de API password_as_md5hash)
#
# Author: Thilo Gass <thilo.gass@gmail.com>
# Git repo: https://github.com/ThiloGa/acme.sh

#-- dns_nm_add() - Add TXT record --------------------------------------
# Usage: dns_nm_add _acme-challenge.subdomain.domain.com "XyZ123..."

dns_nm_add() {
  fulldomain=$1
  txt_value=$2
  _info "Using DNS-01 namemaster hook"
  
  NM_user="${NM_user:-$(_readaccountconf_mutable NM_user)}"
  NM_md5="${NM_md5:-$(_readaccountconf_mutable NM_md5)}"
  if [ -z "$NM_user" ] || [ -z "$NM_md5" ]; then
    NM_user=""
    NM_md5=""
	_err "No auth details provided. Please set user credentials using the \$NM_user and \$NM_md5 environment variables."
    return 1
  fi
  #save the api user and md5 password to the account conf file.
  _debug "Save user and hash"
  _saveaccountconf_mutable NM_user "$NM_user"
  _saveaccountconf_mutable NM_md5 "$NM_md5"
 
 
  zone="$(echo $fulldomain | _egrep_o "[^.]+.[^.]+$")"
  get="https://namemaster.de/api/api.php?User=$NM_user&Password=$NM_md5&Antwort=csv&Int=0&Typ=ACME&Zone=$zone&hostname=$fulldomain&TXT=$txt_value&Action=Auto&Lifetime=3600"
  erg="$(_get "$get")"

  if [ "$?" != "0" ]; then
    _err "error $action $zone TXT: $txt"
    _err "Error $?"
	return 1
  fi

  if _contains "$erg" "Success"; then
    _info "Success, TXT Added, OK"
  else
    _err "error Auto $zone TXT: $txt erg: $erg"
    return 1
  fi

  _debug "ok Auto $zone TXT: $txt erg: $erg"
  return 0
}

dns_nm_rm() {

fulldomain=$1
txt_value=$2

  NM_user="${NM_user:-$(_readaccountconf_mutable NM_user)}"
  NM_md5="${NM_md5:-$(_readaccountconf_mutable NM_md5)}"
  if [ -z "$NM_user" ] || [ -z "$NM_md5" ]; then
    NM_user=""
    NM_md5=""
  	_err "No auth details provided. Please set user credentials using the \$NM_user and \$NM_md5 environment variables."
    return 1
  fi

  zone="$(echo $fulldomain | _egrep_o "[^.]+.[^.]+$")"
  get="https://namemaster.de/api/api.php?User=$NM_user&Password=$NM_md5&Antwort=csv&Int=0&Typ=TXT&Zone=$zone&hostname=$fulldomain&TXT=$txt_value&Action=Delete_IN&TTL=0"
  erg="$(_get "$get")"
  if [ "$?" != "0" ]; then
    _err "error $action $zone TXT: $txt"
	_err "Error $?"
    return 1
  fi

if _contains "$erg" "Success"; then
  _info "Success, TXT removed, OK"

else
  _err "error Auto $zone TXT: $txt erg: $erg"
  return 1
fi

_debug "ok Auto $zone TXT: $txt erg: $erg"
return 0


}
