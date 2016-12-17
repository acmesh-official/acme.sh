#!/usr/bin/env sh

# Cloudxns.com Domain api
#
#CX_Key="1234"
#
#CX_Secret="sADDsdasdgdsf"

CX_Api="https://www.cloudxns.net/api2"

#REST_API
########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_cx_add() {
  fulldomain=$1
  txtvalue=$2

  if [ -z "$CX_Key" ] || [ -z "$CX_Secret" ]; then
    CX_Key=""
    CX_Secret=""
    _err "You don't specify cloudxns.com  api key or secret yet."
    _err "Please create you key and try again."
    return 1
  fi

  REST_API="$CX_Api"

  #save the api key and email to the account conf file.
  _saveaccountconf CX_Key "$CX_Key"
  _saveaccountconf CX_Secret "$CX_Secret"

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

  if [ "$?" = "0" ]; then
    return 0
  fi
  return 1
}

#fulldomain
dns_cx_rm() {
  fulldomain=$1
  REST_API="$CX_Api"
  if _get_root "$fulldomain"; then
    record_id=""
    existing_records "$_domain" "$_sub_domain"
    if ! [ "$record_id" = "" ]; then
      _rest DELETE "record/$record_id/$_domain_id" "{}"
      _info "Deleted record ${fulldomain}"
    fi
  fi
}

#usage:  root  sub
#return if the sub record already exists.
#echos the existing records count.
# '0' means doesn't exist
existing_records() {
  _debug "Getting txt records"
  root=$1
  sub=$2
  count=0
  if ! _rest GET "record/$_domain_id?:domain_id?host_id=0&offset=0&row_num=100"; then
    return 1
  fi

  seg=$(printf "%s\n" "$response" | _egrep_o '{[^{]*host":"'"$_sub_domain"'"[^}]*\}')
  _debug seg "$seg"
  if [ -z "$seg" ]; then
    return 0
  fi

  if printf "%s" "$response" | grep '"type":"TXT"' >/dev/null; then
    count=1
    record_id=$(printf "%s\n" "$seg" | _egrep_o '"record_id":"[^"]*"' | cut -d : -f 2 | tr -d \" | _head_n 1)
    _debug record_id "$record_id"
    return 0
  fi

}

#add the txt record.
#usage: root  sub  txtvalue
add_record() {
  root=$1
  sub=$2
  txtvalue=$3
  fulldomain="$sub.$root"

  _info "Adding record"

  if ! _rest POST "record" "{\"domain_id\": $_domain_id, \"host\":\"$_sub_domain\", \"value\":\"$txtvalue\", \"type\":\"TXT\",\"ttl\":600, \"line_id\":1}"; then
    return 1
  fi

  return 0
}

#update the txt record
#Usage: root sub txtvalue
update_record() {
  root=$1
  sub=$2
  txtvalue=$3
  fulldomain="$sub.$root"

  _info "Updating record"

  if _rest PUT "record/$record_id" "{\"domain_id\": $_domain_id, \"host\":\"$_sub_domain\", \"value\":\"$txtvalue\", \"type\":\"TXT\",\"ttl\":600, \"line_id\":1}"; then
    return 0
  fi

  return 1
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

  if ! _rest GET "domain"; then
    return 1
  fi

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    if _contains "$response" "$h."; then
      seg=$(printf "%s\n" "$response" | _egrep_o '{[^{]*"'"$h"'."[^}]*}')
      _debug seg "$seg"
      _domain_id=$(printf "%s\n" "$seg" | _egrep_o "\"id\":\"[^\"]*\"" | cut -d : -f 2 | tr -d \")
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
  _debug ep "$ep"
  url="$REST_API/$ep"
  _debug url "$url"

  cdate=$(date -u "+%Y-%m-%d %H:%M:%S UTC")
  _debug cdate "$cdate"

  data="$3"
  _debug data "$data"

  sec="$CX_Key$url$data$cdate$CX_Secret"
  _debug sec "$sec"
  hmac=$(printf "%s" "$sec" | _digest md5 hex)
  _debug hmac "$hmac"

  _H1="API-KEY: $CX_Key"
  _H2="API-REQUEST-DATE: $cdate"
  _H3="API-HMAC: $hmac"
  _H4="Content-Type: application/json"

  if [ "$data" ]; then
    response="$(_post "$data" "$url" "" "$m")"
  else
    response="$(_get "$url")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  if ! _contains "$response" '"message":"success"'; then
    return 1
  fi
  return 0
}
