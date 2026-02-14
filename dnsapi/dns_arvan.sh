#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_arvan_info='ArvanCloud.ir
Site: ArvanCloud.ir
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_arvan
Options:
 Arvan_Token API Token
Issues: github.com/acmesh-official/acme.sh/issues/6788
Author: Abolfazl Rajabpour ( abooraja ) ( mizekar.com )
'

ARVAN_API_URL="https://napi.arvancloud.ir/cdn/4.0/domains"

########  Public functions #####################

#Usage: dns_arvan_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_arvan_add() {
  fulldomain=$1
  txtvalue=$2
  _info "Using Arvan"

  Arvan_Token="${Arvan_Token:-$(_readaccountconf_mutable Arvan_Token)}"

  if [ -z "$Arvan_Token" ]; then
    _err "You didn't specify \"Arvan_Token\" token yet."
    _err "You can get yours from here https://npanel.arvancloud.ir/profile/api-keys"
    return 1
  fi
  #save the api token to the account conf file.
  _saveaccountconf_mutable Arvan_Token "$Arvan_Token"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _info "Adding record"
  if _arvan_rest POST "$_domain/dns-records" "{\"type\":\"TXT\",\"name\":\"$_sub_domain\",\"value\":{\"text\":\"$txtvalue\"},\"ttl\":120}"; then
    if _contains "$response" "$txtvalue"; then
      _info "response id is $response"
      _info "Added, OK"
      return 0
    elif _contains "$response" "Record Data is duplicate" || _contains "$response" "duplicate" || _contains "$response" "already exists"; then
      _info "Already exists, OK"
      return 0
    else
      _err "Add txt record error."
      _debug "Response was: $response"
      return 1
    fi
  else
    _err "Add txt record error."
    return 1
  fi
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_arvan_rm() {
  fulldomain=$1
  txtvalue=$2
  _info "Using Arvan"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  Arvan_Token="${Arvan_Token:-$(_readaccountconf_mutable Arvan_Token)}"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting txt records"
  _arvan_rest GET "${_domain}/dns-records"
  if ! printf "%s" "$response" | grep -q "\"current_page\":1"; then
    _err "Error on Arvan Api"
    _err "Please create a github issue with debbug log"
    return 1
  fi

  # جستجوی رکورد با نام و مقدار مشخص
  # الگوهای مختلف برای پیدا کردن record_id
  _record_id=$(echo "$response" | _egrep_o "\"id\":\"[^\"]*\"[^}]*\"type\":\"[Tt][Xx][Tt]\"[^}]*\"name\":\"$_sub_domain\"[^}]*\"value\":[^}]*\"text\":\"$txtvalue\"" | _egrep_o "\"id\":\"[^\"]*\"" | cut -d : -f 2 | tr -d \")
  
  # اگر با الگوی بالا پیدا نشد، الگوی دیگر را امتحان کنیم
  if [ -z "$_record_id" ]; then
    _record_id=$(echo "$response" | _egrep_o "\"name\":\"$_sub_domain\"[^}]*\"type\":\"[Tt][Xx][Tt]\"[^}]*\"value\":[^}]*\"text\":\"$txtvalue\"[^}]*\"id\":\"[^\"]*\"" | _egrep_o "\"id\":\"[^\"]*\"" | cut -d : -f 2 | tr -d \")
  fi
  
  # اگر هنوز پیدا نشد، سعی کنیم از کل response استخراج کنیم
  if [ -z "$_record_id" ]; then
    # پیدا کردن بخش مربوط به این رکورد
    record_block=$(echo "$response" | _egrep_o "\{[^}]*\"name\":\"$_sub_domain\"[^}]*\"type\":\"[Tt][Xx][Tt]\"[^}]*\"value\":[^}]*\"text\":\"$txtvalue\"[^}]*\}")
    if [ -n "$record_block" ]; then
      _record_id=$(echo "$record_block" | _egrep_o "\"id\":\"[^\"]*\"" | cut -d : -f 2 | tr -d \")
    fi
  fi
  
  if [ -z "$_record_id" ]; then
    _err "Could not find record with name '$_sub_domain' and value '$txtvalue'"
    _debug "Response was: $response"
    return 1
  fi
  
  _debug "Found record_id: $_record_id"
  
  if ! _arvan_rest "DELETE" "${_domain}/dns-records/${_record_id}"; then
    _err "Error on Arvan Api"
    return 1
  fi
  _debug "$response"
  
  if _contains "$response" 'dns record deleted' || _contains "$response" 'deleted' || _contains "$response" 'success'; then
    _info "Record deleted successfully"
    return 0
  else
    _err "Failed to delete record"
    return 1
  fi
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
  
  # ابتدا لیست دامنه‌ها را از API بگیریم
  _debug "Getting list of domains from Arvan API"
  if ! _arvan_rest GET ""; then
    _err "Failed to get domains list from Arvan API"
    return 1
  fi
  
  # ذخیره response برای استفاده در حلقه
  domains_list="$response"
  _debug2 "Domains list response: $domains_list"
  
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    # چک کردن وجود دامنه در لیست
    if _contains "$domains_list" "\"domain\":\"$h\""; then
      # استخراج domain_id از response
      # فرمت ممکن: {"id":"xxx","domain":"mizekar.site",...} یا {"domain":"mizekar.site","id":"xxx",...}
      _domain_id=$(echo "$domains_list" | _egrep_o "\"id\":\"[^\"]*\"[^}]*\"domain\":\"$h\"" | _egrep_o "\"id\":\"[^\"]*\"" | cut -d : -f 2 | tr -d \")
      
      # اگر با الگوی بالا پیدا نشد، الگوی دیگر را امتحان کنیم
      if [ -z "$_domain_id" ]; then
        _domain_id=$(echo "$domains_list" | _egrep_o "\"domain\":\"$h\"[^}]*\"id\":\"[^\"]*\"" | _egrep_o "\"id\":\"[^\"]*\"" | cut -d : -f 2 | tr -d \")
      fi
      
      # اگر هنوز پیدا نشد، سعی کنیم از کل response استخراج کنیم
      if [ -z "$_domain_id" ]; then
        # پیدا کردن بخش مربوط به این دامنه
        domain_block=$(echo "$domains_list" | _egrep_o "\{[^}]*\"domain\":\"$h\"[^}]*\}")
        if [ -n "$domain_block" ]; then
          _domain_id=$(echo "$domain_block" | _egrep_o "\"id\":\"[^\"]*\"" | cut -d : -f 2 | tr -d \")
        fi
      fi
      
      if [ "$_domain_id" ]; then
        _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-"$p")
        _domain=$h
        _debug "Found domain: $_domain, sub_domain: $_sub_domain, domain_id: $_domain_id"
        return 0
      else
        _err "Could not extract domain_id for domain: $h"
        return 1
      fi
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

_arvan_rest() {
  mtd="$1"
  ep="$2"
  data="$3"

  token_trimmed=$(echo "$Arvan_Token" | tr -d '"')
  export _H1="Authorization: $token_trimmed"

  if [ "$mtd" = "DELETE" ]; then
    #DELETE Request shouldn't have Content-Type
    _debug data "$data"
    response="$(_post "$data" "$ARVAN_API_URL/$ep" "" "$mtd")"
  elif [ "$mtd" = "POST" ]; then
    export _H2="Content-Type: application/json"
    export _H3="Accept: application/json"
    _debug data "$data"
    response="$(_post "$data" "$ARVAN_API_URL/$ep" "" "$mtd")"
  else
    # برای GET request
    if [ -n "$ep" ]; then
      # اگر ep مشخص شده، به endpoint خاص درخواست می‌زنیم
      response="$(_get "$ARVAN_API_URL/$ep")"
    else
      # اگر ep خالی است، لیست دامنه‌ها را می‌گیریم
      response="$(_get "$ARVAN_API_URL")"
    fi
  fi
  
  # چک کردن موفقیت درخواست
  if [ "$?" != "0" ]; then
    _err "Error on Arvan API request"
    return 1
  fi
  
  _debug2 response "$response"
  return 0
}
