#!/usr/bin/env sh


########  Public functions #####################

 # Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
# Used to add txt record
#
# Ref: https://docs.microsoft.com/en-us/rest/api/dns/recordsets/createorupdate
#
dns_azure_add() 
{ 
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

   if [ -z "$AZUREDNS_TENANTID" ] ; then
     AZUREDNS_SUBSCRIPTIONID=""
     AZUREDNS_TENANTID=""
     AZUREDNS_APPID="" 
     AZUREDNS_CLIENTSECRET=""  
	 _err "You didn't specify then Azure Tenant ID "
     return 1
   fi

   if  [ -z "$AZUREDNS_APPID" ] ; then
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
  
   if ! _get_root "$fulldomain"  "$AZUREDNS_SUBSCRIPTIONID" "$accesstoken"; then
    _err "invalid domain"
    return 1
   fi
   _debug _domain_id "$_domain_id"
   _debug _sub_domain "$_sub_domain"
   _debug _domain "$_domain"  
  
   acmeRecordURI="https://management.azure.com$(printf '%s' $_domain_id |sed 's/\\//g')/TXT/$_sub_domain?api-version=2017-09-01"
   _debug $acmeRecordURI
   body="{\"properties\": {\"TTL\": 3600, \"TXTRecords\": [{\"value\": [\"$txtvalue\"]}]}}"
   _azure_rest PUT "$acmeRecordURI" "$body" "$accesstoken"
   _debug $response
}

# Usage: fulldomain txtvalue
# Used to remove the txt record after validation
#
# Ref: https://docs.microsoft.com/en-us/rest/api/dns/recordsets/delete
#
dns_azure_rm() 
{ 
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

   if [ -z "$AZUREDNS_TENANTID" ] ; then
     AZUREDNS_SUBSCRIPTIONID=""
     AZUREDNS_TENANTID=""
     AZUREDNS_APPID="" 
     AZUREDNS_CLIENTSECRET=""  
	 _err "You didn't specify the Azure Tenant ID "
     return 1
   fi

   if  [ -z "$AZUREDNS_APPID" ]  ;then
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
	 _err "You didn't specify Azure Client Secret"
     return 1
   fi

   accesstoken=$(_azure_getaccess_token "$AZUREDNS_TENANTID" "$AZUREDNS_APPID" "$AZUREDNS_CLIENTSECRET")
  
   if ! _get_root "$fulldomain"  "$AZUREDNS_SUBSCRIPTIONID" "$accesstoken"; then
    _err "invalid domain"
    return 1
   fi
   _debug _domain_id "$_domain_id"
   _debug _sub_domain "$_sub_domain"
   _debug _domain "$_domain"  
  
   acmeRecordURI="https://management.azure.com$(printf '%s' $_domain_id |sed 's/\\//g')/TXT/$_sub_domain?api-version=2017-09-01"
   _debug $acmeRecordURI
   body="{\"properties\": {\"TTL\": 3600, \"TXTRecords\": [{\"value\": [\"$txtvalue\"]}]}}"
   _azure_rest DELETE "$acmeRecordURI" "" "$accesstoken"
   _debug $response
}

###################  Private functions below ##################################

_azure_rest() {
   m=$1
   ep="$2"
   data="$3"
   accesstoken="$4"
 
   _debug "$ep"

   export _H1="authorization: Bearer $accesstoken"
   export _H2="accept: application/json"
   export _H3="Content-Type: application/json"
   _H1="authorization: Bearer $accesstoken"
   _H2="accept: application/json"
   _H3="Content-Type: application/json"

   if [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$ep" "" "$m")"
   else
    response="$(_get "$ep")"
   fi
   _debug2 response "$response"
   if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
   fi
   return 0
}

## Ref: https://docs.microsoft.com/en-us/azure/active-directory/develop/active-directory-protocols-oauth-service-to-service#request-an-access-token
_azure_getaccess_token() {
   TENANTID=$1
   clientID=$2
   clientSecret=$3
  
   export _H1="accept: application/json"
   export _H2="Content-Type: application/x-www-form-urlencoded"
   export _H3=""
  
   body="resource=$(printf "%s" 'https://management.core.windows.net/'| _url_encode)&client_id=$(printf "%s" $clientID | _url_encode)&client_secret=$(printf "%s" $clientSecret| _url_encode)&grant_type=client_credentials"
   _debug data "$body"
   response="$(_post "$body" "https://login.windows.net/$TENANTID/oauth2/token" "" "POST" )"
   accesstoken=$(printf "%s\n" "$response" | _egrep_o "\"access_token\":\"[^\"]*\"" | head -n 1 | cut -d : -f 2 | tr -d \")
  
   if [ "$?" != "0" ]; then
     _err "error $response"
     return 1
   fi
   printf $accesstoken
   _debug2 response "$response"
   return 0
}

_get_root() {
   domain=$1
   subscriptionId=$2
   accesstoken=$3
   i=2
   p=1

   ## Ref: https://docs.microsoft.com/en-us/rest/api/dns/zones/list
   ## returns up to 100 zones in one response therefore handling more results is not not implemented 
   ## (ZoneListResult with  continuation token for the next page of results)
   ## Per https://docs.microsoft.com/en-us/azure/azure-subscription-service-limits#dns-limits you are limited to 100 Zone/subscriptions anyways 
   ##
   _azure_rest GET "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.Network/dnszones?api-version=2017-09-01" "" $accesstoken 

   # Find matching domain name is Json response
   while true; do
      h=$(printf "%s" "$domain" | cut -d . -f $i-100)
      _debug2 "Checking domain: $h"
      if [ -z "$h" ]; then
        #not valid
        _err "Invalid domain"
        return 1
      fi

    if _contains "$response" "\"name\":\"$h\"" >/dev/null; then
      _domain_id=$(printf "%s\n" "$response" | _egrep_o "\[.\"id\":\"[^\"]*\"" | head -n 1 | cut -d : -f 2 | tr -d \")
      if [ "$_domain_id" ]; then
        _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
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

