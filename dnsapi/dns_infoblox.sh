#!/usr/bin/env sh

## Infoblox API integration by Jason Keller and Elijah Tenai
##
## Report any bugs via https://github.com/jasonkeller/acme.sh

dns_infoblox_add() {

  ## Nothing to see here, just some housekeeping
  fulldomain=$1
  txtvalue=$2
  baseurlnObject="https://$Infoblox_Server/wapi/v2.2.2/record:txt?name=$fulldomain&text=$txtvalue&view=$Infoblox_View"

  _info "Using Infoblox API"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  ## Check for the credentials
  if [ -z "$Infoblox_Creds" ] || [ -z "$Infoblox_Server" ]; then
    Infoblox_Creds=""
    Infoblox_Server=""
    _err "You didn't specify the credentials, server or infoblox view yet (Infoblox_Creds, Infoblox_Server and Infoblox_View)."
    _err "Please set them via EXPORT ([username:password], [ip or hostname]) and try again."
    return 1
  fi

  if [ -z "$Infoblox_View" ]; then
    Infoblox_View="default"
  fi

  ## Save the credentials to the account file
  _saveaccountconf Infoblox_Creds "$Infoblox_Creds"
  _saveaccountconf Infoblox_Server "$Infoblox_Server"
  _saveaccountconf Infoblox_View "$Infoblox_View"

  ## Base64 encode the credentials
  Infoblox_CredsEncoded=$(printf "%b" "$Infoblox_Creds" | _base64)

  ## Construct the HTTP Authorization header
  export _H1="Accept-Language:en-US"
  export _H2="Authorization: Basic $Infoblox_CredsEncoded"

  ## Add the challenge record to the Infoblox grid member
  result="$(_post "" "$baseurlnObject" "" "POST")"

  ## Let's see if we get something intelligible back from the unit
  if [ "$(echo "$result" | _egrep_o "record:txt/.*:.*/$Infoblox_View")" ]; then
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

  ## Base64 encode the credentials
  Infoblox_CredsEncoded="$(printf "%b" "$Infoblox_Creds" | _base64)"

  ## Construct the HTTP Authorization header
  export _H1="Accept-Language:en-US"
  export _H2="Authorization: Basic $Infoblox_CredsEncoded"

  ## Does the record exist?  Let's check.
  baseurlnObject="https://$Infoblox_Server/wapi/v2.2.2/record:txt?name=$fulldomain&text=$txtvalue&view=$Infoblox_View&_return_type=xml-pretty"
  result="$(_get "$baseurlnObject")"

  ## Let's see if we get something intelligible back from the grid
  if [ "$(echo "$result" | _egrep_o "record:txt/.*:.*/$Infoblox_View")" ]; then
    ## Extract the object reference
    objRef="$(printf "%b" "$result" | _egrep_o "record:txt/.*:.*/$Infoblox_View")"
    objRmUrl="https://$Infoblox_Server/wapi/v2.2.2/$objRef"
    ## Delete them! All the stale records!
    rmResult="$(_post "" "$objRmUrl" "" "DELETE")"
    ## Let's see if that worked
    if [ "$(echo "$rmResult" | _egrep_o "record:txt/.*:.*/$Infoblox_View")" ]; then
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
