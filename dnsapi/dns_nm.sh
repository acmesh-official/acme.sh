#!/usr/bin/env sh

#
#NM_user="user"
#
#NM_md5="password_as_md5hash"

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_nm_add() {
  fulldomain=$1
  txt=$2
  
  NM_user="${NM_user:-$(_readaccountconf_mutable NM_user)}"
  NM_md5="${NM_md5:-$(_readaccountconf_mutable NM_md5)}"
  if [ -z "$NM_user" ] || [ -z "$NM_md5" ]; then
    NM_user=""
    NM_md5=""
    _err "You didn't specify a namemaster api user and md5 password hash yet."
    _err "Please create both and try again."
    return 1
  fi
  #save the api user and md5 password to the account conf file.
  _debug "Save user and hash"
  _saveaccountconf_mutable NM_user "$NM_user"
  _saveaccountconf_mutable NM_md5 "$NM_md5"
  zone="$(echo $fulldomain | _egrep_o "[^.]+.[^.]+$")"
  get="https://namemaster.de/api/api.php?User=$NM_user&Password=$NM_md5&Antwort=csv&Int=0&Typ=ACME&Zone=$zone&hostname=$fulldomain&TXT=$txt&Action=Auto&Lifetime=3600"
  erg="$(_get "$get")"
  if [ "$?" != "0" ]; then
    _err "error $action $zone TXT: $txt"
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

fulldomain="${1}"
  txtvalue="${2}"


  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"
  _debug _service "$_service"


  NM_user="${NM_user:-$(_readaccountconf_mutable NM_user)}"
  NM_md5="${NM_md5:-$(_readaccountconf_mutable NM_md5)}"
  if [ -z "$NM_user" ] || [ -z "$NM_md5" ]; then
    NM_user=""
    NM_md5=""
    _err "You didn't specify a namemaster api user and md5 password hash yet."
    _err "Please create both and try again."
    return 1
  fi


  zone="$(echo $fulldomain | _egrep_o "[^.]+.[^.]+$")"
  get="https://namemaster.de/api/api.php?User=$NM_user&Password=$NM_md5&Antwort=csv&Int=0&Typ=TXT&Zone=$zone&hostname=$fulldomain&TXT=$txt&Action=Delete_IN&TTL=0"
  erg="$(_get "$get")"
  if [ "$?" != "0" ]; then
    _err "error $action $zone TXT: $txt"
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



   # nothing to do
   _debug "delete $1 $2 happens automatically through next time of issuing $1"
}
