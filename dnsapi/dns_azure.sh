#!/usr/bin/env sh

WIKI="https://github.com/acmesh-official/acme.sh/wiki/How-to-use-Azure-DNS"

########  Public functions #####################

# Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
# Used to add txt record
#
# Ref: https://docs.microsoft.com/en-us/rest/api/dns/recordsets/createorupdate
#
dns_azure_add() {
  fulldomain=$1
  txtvalue=$2

  AZUREDNS_SUBSCRIPTIONID="${AZUREDNS_SUBSCRIPTIONID:-$(_readaccountconf_mutable AZUREDNS_SUBSCRIPTIONID)}"
  AZUREDNS_TENANTID="${AZUREDNS_TENANTID:-$(_readaccountconf_mutable AZUREDNS_TENANTID)}"
  AZUREDNS_APPID="${AZUREDNS_APPID:-$(_readaccountconf_mutable AZUREDNS_APPID)}"
  AZUREDNS_CLIENTSECRET="${AZUREDNS_CLIENTSECRET:-$(_readaccountconf_mutable AZUREDNS_CLIENTSECRET)}"

  if [ -z "$AZUREDNS_SUBSCRIPTIONID" ]; then
    AZUREDNS_SUBSCRIPTIONID=""
    AZUREDNS_TENANTID=""
    AZUREDNS_APPID=""
    AZUREDNS_CLIENTSECRET=""
    _err "You didn't specify the Azure Subscription ID "
    return 1
  fi

  if [ -z "$AZUREDNS_TENANTID" ]; then
    AZUREDNS_SUBSCRIPTIONID=""
    AZUREDNS_TENANTID=""
    AZUREDNS_APPID=""
    AZUREDNS_CLIENTSECRET=""
    _err "You didn't specify the Azure Tenant ID "
    return 1
  fi

  if [ -z "$AZUREDNS_APPID" ]; then
    AZUREDNS_SUBSCRIPTIONID=""
    AZUREDNS_TENANTID=""
    AZUREDNS_APPID=""
    AZUREDNS_CLIENTSECRET=""
    _err "You didn't specify the Azure App ID"
    return 1
  fi

  if [ -z "$AZUREDNS_CLIENTSECRET" ]; then
    AZUREDNS_SUBSCRIPTIONID=""
    AZUREDNS_TENANTID=""
    AZUREDNS_APPID=""
    AZUREDNS_CLIENTSECRET=""
    _err "You didn't specify the Azure Client Secret"
    return 1
  fi
  #save account details to account conf file.
  _saveaccountconf_mutable AZUREDNS_SUBSCRIPTIONID "$AZUREDNS_SUBSCRIPTIONID"
  _saveaccountconf_mutable AZUREDNS_TENANTID "$AZUREDNS_TENANTID"
  _saveaccountconf_mutable AZUREDNS_APPID "$AZUREDNS_APPID"
  _saveaccountconf_mutable AZUREDNS_CLIENTSECRET "$AZUREDNS_CLIENTSECRET"

  accesstoken=$(_azure_getaccess_token "$AZUREDNS_TENANTID" "$AZUREDNS_APPID" "$AZUREDNS_CLIENTSECRET")

  if ! _get_root "$fulldomain" "$AZUREDNS_SUBSCRIPTIONID" "$accesstoken"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  acmeRecordURI="https://management.azure.com$(printf '%s' "$_domain_id" | sed 's/\\//g')/TXT/$_sub_domain?api-version=2017-09-01"
  _debug "$acmeRecordURI"
  # Get existing TXT record
  _azure_rest GET "$acmeRecordURI" "" "$accesstoken"
  values="{\"value\":[\"$txtvalue\"]}"
  timestamp="$(_time)"
  if [ "$_code" = "200" ]; then
    vlist="$(echo "$response" | _egrep_o "\"value\"\\s*:\\s*\\[\\s*\"[^\"]*\"\\s*]" | cut -d : -f 2 | tr -d "[]\"")"
    _debug "existing TXT found"
    _debug "$vlist"
    existingts="$(echo "$response" | _egrep_o "\"acmetscheck\"\\s*:\\s*\"[^\"]*\"" | _head_n 1 | cut -d : -f 2 | tr -d "\"")"
    if [ -z "$existingts" ]; then
      # the record was not created by acme.sh. Copy the exisiting entires
      existingts=$timestamp
    fi
    _diff="$(_math "$timestamp - $existingts")"
    _debug "existing txt age: $_diff"
    # only use recently added records and discard if older than 2 hours because they are probably orphaned
    if [ "$_diff" -lt 7200 ]; then
      _debug "existing txt value: $vlist"
      for v in $vlist; do
        values="$values ,{\"value\":[\"$v\"]}"
      done
    fi
  fi
  # Add the txtvalue TXT Record
  body="{\"properties\":{\"metadata\":{\"acmetscheck\":\"$timestamp\"},\"TTL\":10, \"TXTRecords\":[$values]}}"
  _azure_rest PUT "$acmeRecordURI" "$body" "$accesstoken"
  if [ "$_code" = "200" ] || [ "$_code" = '201' ]; then
    _info "validation value added"
    return 0
  else
    _err "error adding validation value ($_code)"
    return 1
  fi
}

# Usage: fulldomain txtvalue
# Used to remove the txt record after validation
#
# Ref: https://docs.microsoft.com/en-us/rest/api/dns/recordsets/delete
#
dns_azure_rm() {
  fulldomain=$1
  txtvalue=$2

  AZUREDNS_SUBSCRIPTIONID="${AZUREDNS_SUBSCRIPTIONID:-$(_readaccountconf_mutable AZUREDNS_SUBSCRIPTIONID)}"
  AZUREDNS_TENANTID="${AZUREDNS_TENANTID:-$(_readaccountconf_mutable AZUREDNS_TENANTID)}"
  AZUREDNS_APPID="${AZUREDNS_APPID:-$(_readaccountconf_mutable AZUREDNS_APPID)}"
  AZUREDNS_CLIENTSECRET="${AZUREDNS_CLIENTSECRET:-$(_readaccountconf_mutable AZUREDNS_CLIENTSECRET)}"

  if [ -z "$AZUREDNS_SUBSCRIPTIONID" ]; then
    AZUREDNS_SUBSCRIPTIONID=""
    AZUREDNS_TENANTID=""
    AZUREDNS_APPID=""
    AZUREDNS_CLIENTSECRET=""
    _err "You didn't specify the Azure Subscription ID "
    return 1
  fi

  if [ -z "$AZUREDNS_TENANTID" ]; then
    AZUREDNS_SUBSCRIPTIONID=""
    AZUREDNS_TENANTID=""
    AZUREDNS_APPID=""
    AZUREDNS_CLIENTSECRET=""
    _err "You didn't specify the Azure Tenant ID "
    return 1
  fi

  if [ -z "$AZUREDNS_APPID" ]; then
    AZUREDNS_SUBSCRIPTIONID=""
    AZUREDNS_TENANTID=""
    AZUREDNS_APPID=""
    AZUREDNS_CLIENTSECRET=""
    _err "You didn't specify the Azure App ID"
    return 1
  fi

  if [ -z "$AZUREDNS_CLIENTSECRET" ]; then
    AZUREDNS_SUBSCRIPTIONID=""
    AZUREDNS_TENANTID=""
    AZUREDNS_APPID=""
    AZUREDNS_CLIENTSECRET=""
    _err "You didn't specify the Azure Client Secret"
    return 1
  fi

  accesstoken=$(_azure_getaccess_token "$AZUREDNS_TENANTID" "$AZUREDNS_APPID" "$AZUREDNS_CLIENTSECRET")

  if ! _get_root "$fulldomain" "$AZUREDNS_SUBSCRIPTIONID" "$accesstoken"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  acmeRecordURI="https://management.azure.com$(printf '%s' "$_domain_id" | sed 's/\\//g')/TXT/$_sub_domain?api-version=2017-09-01"
  _debug "$acmeRecordURI"
  # Get existing TXT record
  _azure_rest GET "$acmeRecordURI" "" "$accesstoken"
  timestamp="$(_time)"
  if [ "$_code" = "200" ]; then
    vlist="$(echo "$response" | _egrep_o "\"value\"\\s*:\\s*\\[\\s*\"[^\"]*\"\\s*]" | cut -d : -f 2 | tr -d "[]\"" | grep -v -- "$txtvalue")"
    values=""
    comma=""
    for v in $vlist; do
      values="$values$comma{\"value\":[\"$v\"]}"
      comma=","
    done
    if [ -z "$values" ]; then
      # No values left remove record
      _debug "removing validation record completely $acmeRecordURI"
      _azure_rest DELETE "$acmeRecordURI" "" "$accesstoken"
      if [ "$_code" = "200" ] || [ "$_code" = '204' ]; then
        _info "validation record removed"
      else
        _err "error removing validation record ($_code)"
        return 1
      fi
    else
      # Remove only txtvalue from the TXT Record
      body="{\"properties\":{\"metadata\":{\"acmetscheck\":\"$timestamp\"},\"TTL\":10, \"TXTRecords\":[$values]}}"
      _azure_rest PUT "$acmeRecordURI" "$body" "$accesstoken"
      if [ "$_code" = "200" ] || [ "$_code" = '201' ]; then
        _info "validation value removed"
        return 0
      else
        _err "error removing validation value ($_code)"
        return 1
      fi
    fi
  fi
}

###################  Private functions below ##################################

_azure_rest() {
  m=$1
  ep="$2"
  data="$3"
  accesstoken="$4"

  MAX_REQUEST_RETRY_TIMES=5
  _request_retry_times=0
  while [ "${_request_retry_times}" -lt "$MAX_REQUEST_RETRY_TIMES" ]; do
    _debug3 _request_retry_times "$_request_retry_times"
    export _H1="authorization: Bearer $accesstoken"
    export _H2="accept: application/json"
    export _H3="Content-Type: application/json"
    # clear headers from previous request to avoid getting wrong http code on timeouts
    : >"$HTTP_HEADER"
    _debug "$ep"
    if [ "$m" != "GET" ]; then
      _secure_debug2 "data $data"
      response="$(_post "$data" "$ep" "" "$m")"
    else
      response="$(_get "$ep")"
    fi
    _ret="$?"
    _secure_debug2 "response $response"
    _code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\\r\\n")"
    _debug "http response code $_code"
    if [ "$_code" = "401" ]; then
      # we have an invalid access token set to expired
      _saveaccountconf_mutable AZUREDNS_TOKENVALIDTO "0"
      _err "access denied make sure your Azure settings are correct. See $WIKI"
      return 1
    fi
    # See https://docs.microsoft.com/en-us/azure/architecture/best-practices/retry-service-specific#general-rest-and-retry-guidelines for retryable HTTP codes
    if [ "$_ret" != "0" ] || [ -z "$_code" ] || [ "$_code" = "408" ] || [ "$_code" = "500" ] || [ "$_code" = "503" ] || [ "$_code" = "504" ]; then
      _request_retry_times="$(_math "$_request_retry_times" + 1)"
      _info "REST call error $_code retrying $ep in $_request_retry_times s"
      _sleep "$_request_retry_times"
      continue
    fi
    break
  done
  if [ "$_request_retry_times" = "$MAX_REQUEST_RETRY_TIMES" ]; then
    _err "Error Azure REST called was retried $MAX_REQUEST_RETRY_TIMES times."
    _err "Calling $ep failed."
    return 1
  fi
  response="$(echo "$response" | _normalizeJson)"
  return 0
}

## Ref: https://docs.microsoft.com/en-us/azure/active-directory/develop/active-directory-protocols-oauth-service-to-service#request-an-access-token
_azure_getaccess_token() {
  tenantID=$1
  clientID=$2
  clientSecret=$3

  accesstoken="${AZUREDNS_BEARERTOKEN:-$(_readaccountconf_mutable AZUREDNS_BEARERTOKEN)}"
  expires_on="${AZUREDNS_TOKENVALIDTO:-$(_readaccountconf_mutable AZUREDNS_TOKENVALIDTO)}"

  # can we reuse the bearer token?
  if [ -n "$accesstoken" ] && [ -n "$expires_on" ]; then
    if [ "$(_time)" -lt "$expires_on" ]; then
      # brearer token is still valid - reuse it
      _debug "reusing bearer token"
      printf "%s" "$accesstoken"
      return 0
    else
      _debug "bearer token expired"
    fi
  fi
  _debug "getting new bearer token"

  export _H1="accept: application/json"
  export _H2="Content-Type: application/x-www-form-urlencoded"

  body="resource=$(printf "%s" 'https://management.core.windows.net/' | _url_encode)&client_id=$(printf "%s" "$clientID" | _url_encode)&client_secret=$(printf "%s" "$clientSecret" | _url_encode)&grant_type=client_credentials"
  _secure_debug2 "data $body"
  response="$(_post "$body" "https://login.microsoftonline.com/$tenantID/oauth2/token" "" "POST")"
  _ret="$?"
  _secure_debug2 "response $response"
  response="$(echo "$response" | _normalizeJson)"
  accesstoken=$(echo "$response" | _egrep_o "\"access_token\":\"[^\"]*\"" | _head_n 1 | cut -d : -f 2 | tr -d \")
  expires_on=$(echo "$response" | _egrep_o "\"expires_on\":\"[^\"]*\"" | _head_n 1 | cut -d : -f 2 | tr -d \")

  if [ -z "$accesstoken" ]; then
    _err "no acccess token received. Check your Azure settings see $WIKI"
    return 1
  fi
  if [ "$_ret" != "0" ]; then
    _err "error $response"
    return 1
  fi
  _saveaccountconf_mutable AZUREDNS_BEARERTOKEN "$accesstoken"
  _saveaccountconf_mutable AZUREDNS_TOKENVALIDTO "$expires_on"
  printf "%s" "$accesstoken"
  return 0
}

_get_root() {
  domain=$1
  subscriptionId=$2
  accesstoken=$3
  i=1
  p=1

  ## Ref: https://docs.microsoft.com/en-us/rest/api/dns/zones/list
  ## returns up to 100 zones in one response therefore handling more results is not not implemented
  ## (ZoneListResult with  continuation token for the next page of results)
  ## Per https://docs.microsoft.com/en-us/azure/azure-subscription-service-limits#dns-limits you are limited to 100 Zone/subscriptions anyways
  ##
  _azure_rest GET "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.Network/dnszones?\$top=500&api-version=2017-09-01" "" "$accesstoken"
  # Find matching domain name in Json response
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug2 "Checking domain: $h"
    if [ -z "$h" ]; then
      #not valid
      _err "Invalid domain"
      return 1
    fi

    if _contains "$response" "\"name\":\"$h\"" >/dev/null; then
      _domain_id=$(echo "$response" | _egrep_o "\\{\"id\":\"[^\"]*\\/$h\"" | head -n 1 | cut -d : -f 2 | tr -d \")
      if [ "$_domain_id" ]; then
        if [ "$i" = 1 ]; then
          #create the record at the domain apex (@) if only the domain name was provided as --domain-alias
          _sub_domain="@"
        else
          _sub_domain=$(echo "$domain" | cut -d . -f 1-$p)
        fi
        _domain=$h
        return 0
      fi
      return 1
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}
