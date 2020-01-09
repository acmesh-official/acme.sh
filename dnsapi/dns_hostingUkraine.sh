#!/usr/bin/env sh

# Will be called by acme.sh to add the txt record to https://www.ukraine.com.ua/ api.
# Usage: ./acme.sh --issue -d yourdomain.com [-d '*.yourdomain.com'] --dns dns_hostingUkraine
# API endpoint. 
HostingUkraine_Api="https://adm.tools/api.php"
# Author: Qvinti <qvinti.com@gmail.com>
# Report Bugs here: https://github.com/Neilpang/acme.sh/issues/2683
# Hosting Ukraine API documentation: https://api.adm.tools/osnovnie-polozheniya/dostup-k-api/
# Your login:
HostingUkraine_Login=""
# Your api token:
HostingUkraine_Token=""

########  Public functions #####################
# Used to add txt record
dns_hostingUkraine_add() {
  fulldomain=$1
  txtvalue=$2
  subdomain=$(echo "$fulldomain" | sed -e "s/\.$domain//")

  _hostingUkraine_init

  _info "Adding txt record. ($fulldomain)"
  _hostingUkraine_rest POST "dns_record" "create" "\"domain\":\"$domain\",\"subdomain\":\"$subdomain\",\"type\":\"TXT\",\"data\":\"$txtvalue\""
  if _contains "$response" "\"status\":\"error\""; then
    _err "Add txt record, Failure! ($fulldomain)"
    return 1
  fi
  _info "Add txt record, OK! ($fulldomain)"
  return 0
}

# Used to remove the txt record after validation
dns_hostingUkraine_rm() {
  fulldomain=$1
  txtvalue=$2

  _hostingUkraine_init

  _debug "Getting txt records"
  _hostingUkraine_rest POST "dns_record" "info" "\"domain\":\"$domain\""
  if _contains "$response" "\"status\":\"error\""; then
    _err "Get domain records, Failure! ($domain)"
    return 1
  fi

  ids=$(echo "$response" | _egrep_o "[^{]+${txtvalue}[^}]+" | _egrep_o "id\":[^\,]+" | cut -c5-)
  if [ -z "$ids" ]; then
    _err "Empty TXT records! ($fulldomain: $txtvalue)"
    return 1
  fi

  for id in $ids; do
    stack="${stack:+${stack},}${id}"
  done

  _hostingUkraine_rest POST "dns_record" "delete" "\"domain\":\"$domain\",\"stack\":[$stack]"
  if _contains "$response" "\"status\":\"error\""; then
    _err "Remove txt record, Failure! ($fulldomain: $id)"
    return 1
  fi
  _info "Remove txt record, OK! ($fulldomain: $id)"
  return 0
}

####################  Private functions below ##################################
# Check root zone
_get_root() {
  domain=$1
  if _hostingUkraine_rest POST "dns_record" "info" "\"domain\":\"$domain\""; then
    if _contains "$response" "\"status\":\"success\"" >/dev/null; then
      _info "Get root, OK! ($domain)"
      return 0
    fi
  fi
  _err "Get root, Failure! ($domain)"
  return 1
}

# Check credentials and root zone
_hostingUkraine_init() {
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

  _debug "First detect the root zone"
  if ! _get_root "$domain"; then
    _err "Invalid domain! ($domain)"
    return 1
  fi
}

# Send request to API endpoint
_hostingUkraine_rest() {
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
