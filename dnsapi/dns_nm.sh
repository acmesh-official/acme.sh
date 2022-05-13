#!/usr/bin/env sh

########################################################################
# https://namemaster.de hook script for acme.sh
#
# Environment variables:
#
#  - $NM_user      (your namemaster.de API username)
#  - $NM_sha256       (your namemaster.de API password_as_sha256hash)
#
# Author: Thilo Gass <thilo.gass@gmail.com>
# Git repo: https://github.com/ThiloGa/acme.sh

#-- dns_nm_add() - Add TXT record --------------------------------------
# Usage: dns_nm_add _acme-challenge.subdomain.domain.com "XyZ123..."

namemaster_api="https://namemaster.de/api/api.php"

dns_nm_add() {
  fulldomain=$1
  txt_value=$2
  _info "Using DNS-01 namemaster hook"

  NM_user="${NM_user:-$(_readaccountconf_mutable NM_user)}"
  NM_sha256="${NM_sha256:-$(_readaccountconf_mutable NM_sha256)}"
  if [ -z "$NM_user" ] || [ -z "$NM_sha256" ]; then
    NM_user=""
    NM_sha256=""
    _err "No auth details provided. Please set user credentials using the \$NM_user and \$NM_sha256 environment variables."
    return 1
  fi
  #save the api user and sha256 password to the account conf file.
  _debug "Save user and hash"
  _saveaccountconf_mutable NM_user "$NM_user"
  _saveaccountconf_mutable NM_sha256 "$NM_sha256"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain" "$fulldomain"
    return 1
  fi

  _info "die Zone lautet:" "$zone"

  get="$namemaster_api?User=$NM_user&Password=$NM_sha256&Antwort=csv&Typ=ACME&zone=$zone&hostname=$fulldomain&TXT=$txt_value&Action=Auto&Lifetime=3600"

  if ! erg="$(_get "$get")"; then
    _err "error Adding $fulldomain TXT: $txt_value"
    return 1
  fi

  if _contains "$erg" "Success"; then
    _info "Success, TXT Added, OK"
  else
    _err "error Adding $fulldomain TXT: $txt_value erg: $erg"
    return 1
  fi

  _debug "ok Auto $fulldomain TXT: $txt_value erg: $erg"
  return 0
}

dns_nm_rm() {

  fulldomain=$1
  txtvalue=$2
  _info "TXT enrty in $fulldomain is deleted automatically"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

}

_get_root() {

  domain=$1

  get="$namemaster_api?User=$NM_user&Password=$NM_sha256&Typ=acme&hostname=$domain&Action=getzone&antwort=csv"

  if ! zone="$(_get "$get")"; then
    _err "error getting Zone"
    return 1
  else
    if _contains "$zone" "hostname not found"; then
      return 1
    fi
  fi

}
