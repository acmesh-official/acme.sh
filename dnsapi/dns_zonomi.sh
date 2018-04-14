#!/usr/bin/env sh

#
#ZM_Key="sdfsdfsdfljlbjkljlkjsdfoiwje"
#
#https://zonomi.com dns api

ZM_Api="https://zonomi.com/app/dns/dyndns.jsp"

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_zonomi_add() {
  fulldomain=$1
  txtvalue=$2

  ZM_Key="${ZM_Key:-$(_readaccountconf_mutable ZM_Key)}"

  if [ -z "$ZM_Key" ]; then
    ZM_Key=""
    _err "You don't specify zonomi api key yet."
    _err "Please create your key and try again."
    return 1
  fi

  #save the api key to the account conf file.
  _saveaccountconf_mutable ZM_Key "$ZM_Key"

  _info "Get existing txt records for $fulldomain"
  if ! _zm_request "action=QUERY&name=$fulldomain"; then
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
    _zm_request "$_qstr"
  else
    _debug "Just add record"
    _zm_request "action=SET&type=TXT&name=$fulldomain&value=$txtvalue"
  fi

}

#fulldomain txtvalue
dns_zonomi_rm() {
  fulldomain=$1
  txtvalue=$2

  ZM_Key="${ZM_Key:-$(_readaccountconf_mutable ZM_Key)}"
  if [ -z "$ZM_Key" ]; then
    ZM_Key=""
    _err "You don't specify zonomi api key yet."
    _err "Please create your key and try again."
    return 1
  fi

  _zm_request "action=DELETE&type=TXT&name=$fulldomain"

}

####################  Private functions below ##################################
#qstr
_zm_request() {
  qstr="$1"

  _debug2 "qstr" "$qstr"

  _zm_url="$ZM_Api?api_key=$ZM_Key&$qstr"
  _debug2 "_zm_url" "$_zm_url"
  response="$(_get "$_zm_url")"

  if [ "$?" != "0" ]; then
    return 1
  fi
  _debug2 response "$response"
  _contains "$response" "<is_ok>OK:"
}
