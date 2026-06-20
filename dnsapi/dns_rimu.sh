#!/usr/bin/env sh

#
#RM_Key="sdfsdfsdfljlbjkljlkjsdfoiwje"
#
#https://rimuhosting.com dns api

RM_Api="https://rimuhosting.com/dns/dyndns.jsp"

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_rimu_add() {
  fulldomain=$1
  txtvalue=$2

  RM_Key="${RM_Key:-$(_readaccountconf_mutable RM_Key)}"

  if [ -z "$RM_Key" ]; then
    RM_Key=""
    _err "You did not specify a RimuHosting api key."
    _err "Please create your key here https://rimuhosting.com/cp/apikeys.jsp and try again."
    return 1
  fi

  #save the api key to the account conf file.
  _saveaccountconf_mutable RM_Key "$RM_Key"

  _info "Get existing txt records for $fulldomain"
  if ! _rm_request "action=QUERY&name=$fulldomain"; then
    _err "error"
    return 1
  fi

  if _contains "$response" "<record"; then
    _debug "get and update records"
    _qstr="action[1]=SET&type[1]=TXT&name[1]=$fulldomain&value[1]=$txtvalue"
    _qindex=2
    for t in $(echo "$response" | tr -d "\r\n" | _egrep_o '<action.*</action>' | tr "<" "\n" | grep record | grep 'type="TXT"' | cut -d '"' -f 6); do
      _debug2 t "$t"
      _qstr="$_qstr&action[$_qindex]=SET&type[$_qindex]=TXT&name[$_qindex]=$fulldomain&value[$_qindex]=$t"
      _qindex="$(_math "$_qindex" + 1)"
    done
    _rm_request "$_qstr"
  else
    _debug "Just add record"
    _rm_request "action=SET&type=TXT&name=$fulldomain&value=$txtvalue"
  fi

}

#fulldomain txtvalue
dns_rimu_rm() {
  fulldomain=$1
  txtvalue=$2

  RM_Key="${RM_Key:-$(_readaccountconf_mutable RM_Key)}"
  if [ -z "$RM_Key" ]; then
    RM_Key=""
    _err "You did not specify a RimuHosting api key."
    _err "Please create your key here https://rimuhosting.com/cp/apikeys.jsp and try again."
    return 1
  fi

  _rm_request "action=DELETE&type=TXT&name=$fulldomain"

}

####################  Private functions below ##################################
#qstr
_rm_request() {
  qstr="$1"

  _debug2 "qstr" "$qstr"

  _rm_url="$RM_Api?api_key=$RM_Key&$qstr"
  _debug2 "_rm_url" "$_rm_url"
  response="$(_get "$_rm_url")"

  if [ "$?" != "0" ]; then
    return 1
  fi
  _debug2 response "$response"
  _contains "$response" "<is_ok>OK:"
}
