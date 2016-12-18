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

  if [ -z "$DP_Id" ] || [ -z "$DP_Key" ]; then
    DP_Id=""
    DP_Key=""
    _err "You don't specify dnspod api key and key id yet."
    _err "Please create you key and try again."
    return 1
  fi

  #save the api key and email to the account conf file.
  _saveaccountconf DP_Id "$DP_Id"
  _saveaccountconf DP_Key "$DP_Key"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  existing_records "$_domain" "$_sub_domain"
  _debug count "$count"
  if [ "$?" != "0" ]; then
    _err "Error get existing records."
    return 1
  fi

  if [ "$count" = "0" ]; then
    add_record "$_domain" "$_sub_domain" "$txtvalue"
  else
    update_record "$_domain" "$_sub_domain" "$txtvalue"
  fi
}

#fulldomain txtvalue
dns_dp_rm() {
  fulldomain=$1
  txtvalue=$2
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

  record_id=$(echo "$response" | _egrep_o '{[^{]*"value":"'"$txtvalue"'"' | cut -d , -f 1 | cut -d : -f 2 | tr -d \")
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

#usage:  root  sub
#return if the sub record already exists.
#echos the existing records count.
# '0' means doesn't exist
existing_records() {
  _debug "Getting txt records"
  root=$1
  sub=$2

  if ! _rest POST "Record.List" "login_token=$DP_Id,$DP_Key&domain_id=$_domain_id&sub_domain=$_sub_domain"; then
    return 1
  fi

  if _contains "$response" 'No records'; then
    count=0
    return 0
  fi

  if _contains "$response" "Action completed successful"; then
    count=$(printf "%s" "$response" | grep '<type>TXT</type>' | wc -l | tr -d ' ')
    record_id=$(printf "%s" "$response" | grep '^<id>' | tail -1 | cut -d '>' -f 2 | cut -d '<' -f 1)
    _debug record_id "$record_id"
    return 0
  else
    _err "get existing records error."
    return 1
  fi

  count=0
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

  if _contains "$response" "Action completed successful"; then

    return 0
  fi

  return 1 #error
}

#update the txt record
#Usage: root sub txtvalue
update_record() {
  root=$1
  sub=$2
  txtvalue=$3
  fulldomain="$sub.$root"

  _info "Updating record"

  if ! _rest POST "Record.Modify" "login_token=$DP_Id,$DP_Key&format=json&domain_id=$_domain_id&sub_domain=$_sub_domain&record_type=TXT&value=$txtvalue&record_line=默认&record_id=$record_id"; then
    return 1
  fi

  if _contains "$response" "Action completed successful"; then

    return 0
  fi

  return 1 #error
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
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"
  url="$REST_API/$ep"

  _debug url "$url"

  if [ "$data" ]; then
    _debug2 data "$data"
    response="$(_post "$data" "$url" | tr -d '\r')"
  else
    response="$(_get "$url" | tr -d '\r')"
  fi

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
