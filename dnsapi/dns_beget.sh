#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_beget_info='Beget.com
Site: Beget.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_beget
Options:
 BEGET_User API user
 BEGET_Password API password
Issues: github.com/acmesh-official/acme.sh/issues/6200
Author: ARNik <arnik@arnik.ru>
'

Beget_Api="https://api.beget.com/api"

####################  Public functions ####################

# Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
# Used to add txt record
dns_beget_add() {
  fulldomain=$1
  txtvalue=$2
  _debug "dns_beget_add() $fulldomain $txtvalue"
  fulldomain=$(echo "$fulldomain" | _lower_case)

  Beget_Username="${Beget_Username:-$(_readaccountconf_mutable Beget_Username)}"
  Beget_Password="${Beget_Password:-$(_readaccountconf_mutable Beget_Password)}"

  if [ -z "$Beget_Username" ] || [ -z "$Beget_Password" ]; then
    Beget_Username=""
    Beget_Password=""
    _err "You must export variables: Beget_Username, and Beget_Password"
    return 1
  fi

  #save the credentials to the account conf file.
  _saveaccountconf_mutable Beget_Username "$Beget_Username"
  _saveaccountconf_mutable Beget_Password "$Beget_Password"

  _info "Prepare subdomain."
  if ! _prepare_subdomain "$fulldomain"; then
    _err "Can't prepare subdomain."
    return 1
  fi

  _info "Get domain records"
  data="{\"fqdn\":\"$fulldomain\"}"
  res=$(_api_call "$Beget_Api/dns/getData" "$data")
  if ! _is_api_reply_ok "$res"; then
    _err "Can't get domain records."
    return 1
  fi

  _info "Add new TXT record"
  data="{\"fqdn\":\"$fulldomain\",\"records\":{"
  data=${data}$(_parce_records "$res" "A")
  data=${data}$(_parce_records "$res" "AAAA")
  data=${data}$(_parce_records "$res" "CAA")
  data=${data}$(_parce_records "$res" "MX")
  data=${data}$(_parce_records "$res" "SRV")
  data=${data}$(_parce_records "$res" "TXT")
  data=$(echo "$data" | sed 's/,$//')
  data=${data}'}}'

  str=$(_txt_to_dns_json "$txtvalue")
  data=$(_add_record "$data" "TXT" "$str")

  res=$(_api_call "$Beget_Api/dns/changeRecords" "$data")
  if ! _is_api_reply_ok "$res"; then
    _err "Can't change domain records."
    return 1
  fi

  return 0
}

# Usage: fulldomain txtvalue
# Used to remove the txt record after validation
dns_beget_rm() {
  fulldomain=$1
  txtvalue=$2
  _debug "dns_beget_rm() $fulldomain $txtvalue"
  fulldomain=$(echo "$fulldomain" | _lower_case)

  Beget_Username="${Beget_Username:-$(_readaccountconf_mutable Beget_Username)}"
  Beget_Password="${Beget_Password:-$(_readaccountconf_mutable Beget_Password)}"

  _info "Get current domain records"
  data="{\"fqdn\":\"$fulldomain\"}"
  res=$(_api_call "$Beget_Api/dns/getData" "$data")
  if ! _is_api_reply_ok "$res"; then
    _err "Can't get domain records."
    return 1
  fi

  _info "Remove TXT record"
  data="{\"fqdn\":\"$fulldomain\",\"records\":{"
  data=${data}$(_parce_records "$res" "A")
  data=${data}$(_parce_records "$res" "AAAA")
  data=${data}$(_parce_records "$res" "CAA")
  data=${data}$(_parce_records "$res" "MX")
  data=${data}$(_parce_records "$res" "SRV")
  data=${data}$(_parce_records "$res" "TXT")
  data=$(echo "$data" | sed 's/,$//')
  data=${data}'}}'

  str=$(_txt_to_dns_json "$txtvalue")
  data=$(_rm_record "$data" "$str")

  res=$(_api_call "$Beget_Api/dns/changeRecords" "$data")
  if ! _is_api_reply_ok "$res"; then
    _err "Can't change domain records."
    return 1
  fi

  return 0
}

####################  Private functions below ####################

# Create subdomain if needed
# Usage: _prepare_subdomain [fulldomain]
_prepare_subdomain() {
  fulldomain=$1

  _info "Detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  if [ -z "$_sub_domain" ]; then
    _debug "$fulldomain is a root domain."
    return 0
  fi

  _info "Get subdomain list"
  res=$(_api_call "$Beget_Api/domain/getSubdomainList")
  if ! _is_api_reply_ok "$res"; then
    _err "Can't get subdomain list."
    return 1
  fi

  if _contains "$res" "\"fqdn\":\"$fulldomain\""; then
    _debug "Subdomain $fulldomain already exist."
    return 0
  fi

  _info "Subdomain $fulldomain does not exist. Let's create one."
  data="{\"subdomain\":\"$_sub_domain\",\"domain_id\":$_domain_id}"
  res=$(_api_call "$Beget_Api/domain/addSubdomainVirtual" "$data")
  if ! _is_api_reply_ok "$res"; then
    _err "Can't create subdomain."
    return 1
  fi

  _debug "Cleanup subdomen records"
  data="{\"fqdn\":\"$fulldomain\",\"records\":{}}"
  res=$(_api_call "$Beget_Api/dns/changeRecords" "$data")
  if ! _is_api_reply_ok "$res"; then
    _debug "Can't cleanup $fulldomain records."
  fi

  data="{\"fqdn\":\"www.$fulldomain\",\"records\":{}}"
  res=$(_api_call "$Beget_Api/dns/changeRecords" "$data")
  if ! _is_api_reply_ok "$res"; then
    _debug "Can't cleanup www.$fulldomain records."
  fi

  return 0
}

# Usage: _get_root _acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
# _domain_id=32436365
_get_root() {
  fulldomain=$1
  i=1
  p=1

  _debug "Get domain list"
  res=$(_api_call "$Beget_Api/domain/getList")
  if ! _is_api_reply_ok "$res"; then
    _err "Can't get domain list."
    return 1
  fi

  while true; do
    h=$(printf "%s" "$fulldomain" | cut -d . -f "$i"-100)
    _debug h "$h"

    if [ -z "$h" ]; then
      return 1
    fi

    if _contains "$res" "$h"; then
      _domain_id=$(echo "$res" | _egrep_o "\"id\":[0-9]*,\"fqdn\":\"$h\"" | cut -d , -f1 | cut -d : -f2)
      if [ "$_domain_id" ]; then
        if [ "$h" != "$fulldomain" ]; then
          _sub_domain=$(echo "$fulldomain" | cut -d . -f 1-"$p")
        else
          _sub_domain=""
        fi
        _domain=$h
        return 0
      fi
      return 1
    fi
    p="$i"
    i=$(_math "$i" + 1)
  done
  return 1
}

# Parce DNS records from json string
# Usage: _parce_records [j_str] [record_name]
_parce_records() {
  j_str=$1
  record_name=$2
  res="\"$record_name\":["
  res=${res}$(echo "$j_str" | _egrep_o "\"$record_name\":\[.*" | cut -d '[' -f2 | cut -d ']' -f1)
  res=${res}"],"
  echo "$res"
}

# Usage: _add_record [data] [record_name] [record_data]
_add_record() {
  data=$1
  record_name=$2
  record_data=$3
  echo "$data" | sed "s/\"$record_name\":\[/\"$record_name\":\[$record_data,/" | sed "s/,\]/\]/"
}

# Usage: _rm_record [data] [record_data]
_rm_record() {
  data=$1
  record_data=$2
  echo "$data" | sed "s/$record_data//g" | sed "s/,\+/,/g" |
    sed "s/{,/{/g" | sed "s/,}/}/g" |
    sed "s/\[,/\[/g" | sed "s/,\]/\]/g"
}

_txt_to_dns_json() {
  echo "{\"ttl\":600,\"txtdata\":\"$1\"}"
}

# Usage: _api_call [api_url] [input_data]
_api_call() {
  api_url="$1"
  input_data="$2"

  _debug "_api_call $api_url"
  _debug "Request: $input_data"

  # res=$(curl -s -L -D ./http.header \
  # "$api_url" \
  # --data-urlencode login=$Beget_Username \
  # --data-urlencode passwd=$Beget_Password \
  # --data-urlencode input_format=json \
  # --data-urlencode output_format=json \
  # --data-urlencode "input_data=$input_data")

  url="$api_url?login=$Beget_Username&passwd=$Beget_Password&input_format=json&output_format=json"
  if [ -n "$input_data" ]; then
    url=${url}"&input_data="
    url=${url}$(echo "$input_data" | _url_encode)
  fi
  res=$(_get "$url")

  _debug "Reply: $res"
  echo "$res"
}

# Usage: _is_api_reply_ok [api_reply]
_is_api_reply_ok() {
  _contains "$1" '^{"status":"success","answer":{"status":"success","result":.*}}$'
}
