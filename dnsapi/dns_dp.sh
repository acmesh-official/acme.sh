#!/usr/bin/env sh

# Dnspod.cn Domain api
#
#DP_Id="1234"
#
#DP_Key="sADDsdasdgdsf"

REST_API="https://dnsapi.cn"

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_dp_add() {
  fulldomain=$1
  txtvalue=$2

  DP_Id="${DP_Id:-$(_readaccountconf_mutable DP_Id)}"
  DP_Key="${DP_Key:-$(_readaccountconf_mutable DP_Key)}"
  if [ -z "$DP_Id" ] || [ -z "$DP_Key" ]; then
    DP_Id=""
    DP_Key=""
    _err "You don't specify dnspod api key and key id yet."
    _err "Please create you key and try again."
    return 1
  fi

  #save the api key and email to the account conf file.
  _saveaccountconf_mutable DP_Id "$DP_Id"
  _saveaccountconf_mutable DP_Key "$DP_Key"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  add_record "$_domain" "$_sub_domain" "$txtvalue"

}

#fulldomain txtvalue
dns_dp_rm() {
  fulldomain=$1
  txtvalue=$2

  DP_Id="${DP_Id:-$(_readaccountconf_mutable DP_Id)}"
  DP_Key="${DP_Key:-$(_readaccountconf_mutable DP_Key)}"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  if ! _rest POST "Record.List" "login_token=$DP_Id,$DP_Key&format=json&domain_id=$_domain_id&sub_domain=$_sub_domain"; then
    _err "Record.Lis error."
    return 1
  fi

  if _contains "$response" 'No records'; then
    _info "Don't need to remove."
    return 0
  fi

  record_id=$(echo "$response" | tr "{" "\n" | grep -- "$txtvalue" | grep '^"id"' | cut -d : -f 2 | cut -d '"' -f 2)
  _debug record_id "$record_id"
  if [ -z "$record_id" ]; then
    _err "Can not get record id."
    return 1
  fi

  if ! _rest POST "Record.Remove" "login_token=$DP_Id,$DP_Key&format=json&domain_id=$_domain_id&record_id=$record_id"; then
    _err "Record.Remove error."
    return 1
  fi

  _contains "$response" "Action completed successful"

}

#add the txt record.
#usage: root  sub  txtvalue
add_record() {
  root=$1
  sub=$2
  txtvalue=$3
  fulldomain="$sub.$root"

  _info "Adding record"

  if ! _rest POST "Record.Create" "login_token=$DP_Id,$DP_Key&format=json&domain_id=$_domain_id&sub_domain=$_sub_domain&record_type=TXT&value=$txtvalue&record_line=默认"; then
    return 1
  fi

  _contains "$response" "Action completed successful" || _contains "$response" "Domain record already exists"
}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
# _domain_id=sdjkglgdfewsdfg
_get_root() {
  domain=$1
  i=2
  p=1
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    if ! _rest POST "Domain.Info" "login_token=$DP_Id,$DP_Key&format=json&domain=$h"; then
      return 1
    fi

    if _contains "$response" "Action completed successful"; then
      _domain_id=$(printf "%s\n" "$response" | _egrep_o "\"id\":\"[^\"]*\"" | cut -d : -f 2 | tr -d \")
      _debug _domain_id "$_domain_id"
      if [ "$_domain_id" ]; then
        _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
        _debug _sub_domain "$_sub_domain"
        _domain="$h"
        _debug _domain "$_domain"
        return 0
      fi
      return 1
    fi
    p="$i"
    i=$(_math "$i" + 1)
  done
  return 1
}

#Usage: method  URI  data
_rest() {
  m="$1"
  ep="$2"
  data="$3"
  _debug "$ep"
  url="$REST_API/$ep"

  _debug url "$url"

  if [ "$m" = "GET" ]; then
    response="$(_get "$url" | tr -d '\r')"
  else
    _debug2 data "$data"
    response="$(_post "$data" "$url" | tr -d '\r')"
  fi

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
