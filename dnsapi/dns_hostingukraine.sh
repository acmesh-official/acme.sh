#!/usr/bin/env sh

# Author: Qvinti (Aleksandr Zaitsev) <qvinti.com@gmail.com>
# Report Bugs here: https://github.com/Neilpang/acme.sh/issues/2683 or https://www.ukraine.com.ua/forum/domennie-imena/acmesh-dnsapi-dlya-hosting-Ukra.html
# Will be called by acme.sh to add the txt record to https://www.ukraine.com.ua/ DNS api.
# Hosting Ukraine API documentation: https://api.adm.tools/osnovnie-polozheniya/dostup-k-api/
# Usage: ./acme.sh --issue -d yourdomain.com [-d '*.yourdomain.com'] --dns dns_hostingukraine
# API endpoint:
HostingUkraine_Api="https://adm.tools/api.php"
# Your login:
HostingUkraine_Login=""
# Your api token:
HostingUkraine_Token=""

########  Public functions #####################
# Used to add txt record
#fulldomain=_acme-challenge.yourDomain.com
#txtvalue=txt_data_value
dns_hostingukraine_add() {
  fulldomain=$1
  txtvalue=$2

  _hostingukraine_init

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "Invalid root domain for: ($fulldomain)"
    return 1
  fi

  _info "Adding txt record. ($fulldomain)"
  _hostingukraine_api_request POST "dns_record" "create" "\"domain\":\"$_domain\",\"subdomain\":\"$_sub_domain\",\"type\":\"TXT\",\"data\":\"$txtvalue\""
  if _contains "$response" "\"status\":\"error\""; then
    _err "Add txt record, Failure! ($fulldomain)"
    return 1
  fi
  _info "Add txt record, OK! ($fulldomain)"
  return 0
}

# Used to remove the txt record after validation
#fulldomain=_acme-challenge.yourDomain.com
#txtvalue=txt_data_value
dns_hostingukraine_rm() {
  fulldomain=$1
  txtvalue=$2

  _hostingukraine_init

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "Invalid root domain for: ($fulldomain)"
    return 1
  fi

  _debug "Getting txt records"
  _hostingukraine_api_request POST "dns_record" "info" "\"domain\":\"$_domain\""
  if _contains "$response" "\"status\":\"error\""; then
    _err "Get domain records, Failure! ($_domain)"
    return 1
  fi

  ids=$(echo "$response" | _egrep_o "[^{]+${txtvalue}[^}]+" | _egrep_o "id\":[^\,]+" | cut -c5-)
  _debug ids "$ids"
  if [ -z "$ids" ]; then
    _err "Empty TXT records! ($fulldomain: $txtvalue)"
    return 1
  fi

  for id in $ids; do
    stack="${stack:+${stack},}${id}"
  done

  _hostingukraine_api_request POST "dns_record" "delete" "\"domain\":\"$_domain\",\"stack\":[$stack]"
  if _contains "$response" "\"status\":\"error\""; then
    _err "Remove txt record, Failure! ($fulldomain: $id)"
    return 1
  fi
  _info "Remove txt record, OK! ($fulldomain: $id)"
  return 0
}

####################  Private functions below ##################################
# Check root zone
#domain=_acme-challenge.yourDomain.com
#returns
# _sub_domain=_acme-challenge
# _domain=yourDomain.com
_get_root() {
  domain=$1
  i=1
  p=1

  _hostingukraine_api_request POST "dns_domain" "info" "\"search\":\"\""

  while true; do
    host=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug host "$host"
    if [ -z "$host" ]; then
      _err "Get root, Failure! ($domain)"
      return 1
    fi

    if _contains "$response" "\"name\":\"$host\""; then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
      _domain=$host
      _debug fulldomain "$domain"
      _debug _sub_domain "$_sub_domain"
      _debug _domain "$_domain"
      _info "Get root, OK! ($host)"
      return 0
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  _err "Get root, Error! ($domain)"
  return 1
}

# Check credentials and root zone
_hostingukraine_init() {
  HostingUkraine_Login="${HostingUkraine_Login:-$(_readaccountconf_mutable HostingUkraine_Login)}"
  HostingUkraine_Token="${HostingUkraine_Token:-$(_readaccountconf_mutable HostingUkraine_Token)}"
  if [ -z "$HostingUkraine_Login" ] || [ -z "$HostingUkraine_Token" ]; then
    HostingUkraine_Login=""
    HostingUkraine_Token=""
    _err "You didn't specify a Hosting Ukraine account or token yet."
    _err "Please create the account and token and try again. Info: https://api.adm.tools/osnovnie-polozheniya/dostup-k-api/"
    return 1
  fi

  _saveaccountconf_mutable HostingUkraine_Login "$HostingUkraine_Login"
  _saveaccountconf_mutable HostingUkraine_Token "$HostingUkraine_Token"
}

# Send request to API endpoint
#request_method=POST
#class=dns_domain|dns_record
#method=info|create|delete
#data=part_of_json_data
_hostingukraine_api_request() {
  request_method=$1
  class=$2
  method=$3
  data=$4

  response="$(_post "{\"auth_login\":\"$HostingUkraine_Login\",\"auth_token\":\"$HostingUkraine_Token\",\"class\":\"$class\",\"method\":\"$method\",$data}" "$HostingUkraine_Api" "" "$request_method" "application/json")"

  if [ "$?" != "0" ]; then
    _err "error $response"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
