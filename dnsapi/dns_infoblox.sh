#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_infoblox_info='Infoblox.com
Site: Infoblox.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_infoblox
Options:
 Infoblox_Creds Credentials. E.g. "username:password"
 Infoblox_Server Server hostname. IP or FQDN of infoblox appliance
Issues: github.com/jasonkeller/acme.sh
Author: Jason Keller, Elijah Tenai
'

dns_infoblox_add() {

  ## Nothing to see here, just some housekeeping
  fulldomain=$1
  txtvalue=$2

  _info "Using Infoblox API"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  ## Check for the credentials
  if [ -z "$Infoblox_Creds" ] || [ -z "$Infoblox_Server" ]; then
    Infoblox_Creds=""
    Infoblox_Server=""
    _err "You didn't specify the Infoblox credentials or server (Infoblox_Creds; Infoblox_Server)."
    _err "Please set them via EXPORT Infoblox_Creds=username:password or EXPORT Infoblox_server=ip/hostname and try again."
    return 1
  fi

  if [ -z "$Infoblox_View" ]; then
    _info "No Infoblox_View set, using fallback value 'default'"
    Infoblox_View="default"
  fi

  ## Save the credentials to the account file
  _saveaccountconf Infoblox_Creds "$Infoblox_Creds"
  _saveaccountconf Infoblox_Server "$Infoblox_Server"
  _saveaccountconf Infoblox_View "$Infoblox_View"

  ## URLencode Infoblox View to deal with e.g. spaces
  Infoblox_ViewEncoded=$(printf "%b" "$Infoblox_View" | _url_encode)

  ## Base64 encode the credentials
  Infoblox_CredsEncoded=$(printf "%b" "$Infoblox_Creds" | _base64)

  ## Construct the HTTP Authorization header
  export _H1="Accept-Language:en-US"
  export _H2="Authorization: Basic $Infoblox_CredsEncoded"

  ## Construct the request URL
  baseurlnObject="https://$Infoblox_Server/wapi/v2.2.2/record:txt?name=$fulldomain&text=$txtvalue&view=${Infoblox_ViewEncoded}"

  ## Add the challenge record to the Infoblox grid member
  result="$(_post "" "$baseurlnObject" "" "POST")"

  ## Let's see if we get something intelligible back from the unit
  if [ "$(echo "$result" | _egrep_o "record:txt/.*:.*/${Infoblox_ViewEncoded}")" ]; then
    _info "Successfully created the txt record"
    return 0
  else
    _err "Error encountered during record addition"
    _err "$result"
    return 1
  fi

}

dns_infoblox_rm() {

  ## Nothing to see here, just some housekeeping
  fulldomain=$1
  txtvalue=$2

  _info "Using Infoblox API"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  ## URLencode Infoblox View to deal with e.g. spaces
  Infoblox_ViewEncoded=$(printf "%b" "$Infoblox_View" | _url_encode)

  ## Base64 encode the credentials
  Infoblox_CredsEncoded="$(printf "%b" "$Infoblox_Creds" | _base64)"

  ## Construct the HTTP Authorization header
  export _H1="Accept-Language:en-US"
  export _H2="Authorization: Basic $Infoblox_CredsEncoded"

  ## Does the record exist?  Let's check.
  baseurlnObject="https://$Infoblox_Server/wapi/v2.2.2/record:txt?name=$fulldomain&text=$txtvalue&view=${Infoblox_ViewEncoded}&_return_type=xml-pretty"
  result="$(_get "$baseurlnObject")"

  ## Let's see if we get something intelligible back from the grid
  if [ "$(echo "$result" | _egrep_o "record:txt/.*:.*/${Infoblox_ViewEncoded}")" ]; then
    ## Extract the object reference
    objRef="$(printf "%b" "$result" | _egrep_o "record:txt/.*:.*/${Infoblox_ViewEncoded}")"
    objRmUrl="https://$Infoblox_Server/wapi/v2.2.2/$objRef"
    ## Delete them! All the stale records!
    rmResult="$(_post "" "$objRmUrl" "" "DELETE")"
    ## Let's see if that worked
    if [ "$(echo "$rmResult" | _egrep_o "record:txt/.*:.*/${Infoblox_ViewEncoded}")" ]; then
      _info "Successfully deleted $objRef"
      return 0
    else
      _err "Error occurred during txt record delete"
      _err "$rmResult"
      return 1
    fi
  else
    _err "Record to delete didn't match an existing record"
    _err "$result"
    return 1
  fi
}

####################  Private functions below ##################################
