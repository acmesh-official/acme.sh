#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_west_cn_info='West.cn
Site: West.cn
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_west_cn
Options:
 WEST_Username API username
 WEST_Key API Key. Set at https://www.west.cn/manager/API/APIconfig.asp
Issues: github.com/acmesh-official/acme.sh/issues/4894
'

REST_API="https://api.west.cn/API/v2"

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_west_cn_add() {
  fulldomain=$1
  txtvalue=$2

  WEST_Username="${WEST_Username:-$(_readaccountconf_mutable WEST_Username)}"
  WEST_Key="${WEST_Key:-$(_readaccountconf_mutable WEST_Key)}"
  if [ -z "$WEST_Username" ] || [ -z "$WEST_Key" ]; then
    WEST_Username=""
    WEST_Key=""
    _err "You don't specify west api key and username yet."
    _err "Please set you key and try again."
    return 1
  fi

  #save the api key and email to the account conf file.
  _saveaccountconf_mutable WEST_Username "$WEST_Username"
  _saveaccountconf_mutable WEST_Key "$WEST_Key"

  add_record "$fulldomain" "$txtvalue"
}

#Usage: rm _acme-challenge.www.domain.com
dns_west_cn_rm() {
  fulldomain=$1
  txtvalue=$2

  WEST_Username="${WEST_Username:-$(_readaccountconf_mutable WEST_Username)}"
  WEST_Key="${WEST_Key:-$(_readaccountconf_mutable WEST_Key)}"

  if ! _rest POST "domain/dns/" "act=dnsrec.list&username=$WEST_Username&apikey=$WEST_Key&domain=$fulldomain&hostname=$fulldomain&record_type=TXT"; then
    _err "dnsrec.list error."
    return 1
  fi

  if _contains "$response" 'no records'; then
    _info "Don't need to remove."
    return 0
  fi

  record_id=$(echo "$response" | tr "{" "\n" | grep -- "$txtvalue" | grep '^"record_id"' | cut -d : -f 2 | cut -d ',' -f 1)
  _debug record_id "$record_id"
  if [ -z "$record_id" ]; then
    _err "Can not get record id."
    return 1
  fi

  if ! _rest POST "domain/dns/" "act=dnsrec.remove&username=$WEST_Username&apikey=$WEST_Key&domain=$fulldomain&hostname=$fulldomain&record_id=$record_id"; then
    _err "dnsrec.remove error."
    return 1
  fi

  _contains "$response" "success"
}

#add the txt record.
#usage: add fulldomain txtvalue
add_record() {
  fulldomain=$1
  txtvalue=$2

  _info "Adding record"

  if ! _rest POST "domain/dns/" "act=dnsrec.add&username=$WEST_Username&apikey=$WEST_Key&domain=$fulldomain&hostname=$fulldomain&record_type=TXT&record_value=$txtvalue"; then
    return 1
  fi

  _contains "$response" "success"
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
