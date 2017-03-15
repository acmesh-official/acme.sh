#!/usr/bin/env sh

dns_infoblox_add() {

  fulldomain=$1
  txtvalue=$2

  baseurlnObject="https://$Infoblox_Server/wapi/v2.2.2/record:txt?name=$fulldomain&text=$txtvalue"

  _info "Using Infoblox API"

  _debug fulldomain "$fulldomain"

  _debug txtvalue "$txtvalue"

  #_err "Not implemented!"

    if [ -z "$Infoblox_Creds" ] || [ -z "$Infoblox_Server" ]; then
    Infoblox_Creds=""
    Infoblox_Server=""
    _err "You didn't specify the credentials or server yet (Infoblox_Creds and Infoblox_Server)."
    _err "Please set them via EXPORT ([username:password] and [ip or hostname]) and try again."
    return 1
  fi

  #save the login info to the account conf file.
  _saveaccountconf Infoblox_Creds "$Infoblox_Creds"
  _saveaccountconf Infoblox_Server "$Infoblox_Server"

result=`curl -k -u $Infoblox_Creds -X POST $baseurlnObject`

if _info "$result" | grep -Eq 'record:txt/.*:.*/default'; then
  _info "Successfully created the txt record"
  return 0
else
  _info "Error encountered during record addition"
  _info $result
  _err $result
   return 1
fi

}

dns_infoblox_rm() {

  fulldomain=$1
  txtvalue=$2

  _info "Using Infoblox API"

  _debug fulldomain "$fulldomain"

  _debug txtvalue "$txtvalue"

 # Does the record exist?

baseurlnObject="https://$Infoblox_Server/wapi/v2.2.2/record:txt?name=$fulldomain&text=$txtvalue&_return_type=xml-pretty"

_info $baseurlnObject

result=`curl -k -u $Infoblox_Creds -X GET $baseurlnObject`

if _info "$result" | grep -Eq 'record:txt/.*:.*/default'; then
    # Extract object ref
    objRef=`grep -Po 'record:txt/.*:.*/default' <<< $result`
    objRmUrl="https://$Infoblox_Server/wapi/v2.2.2/$objRef"
    rmResult=`curl -k -u $Infoblox_Creds -X DELETE $objRmUrl`
    # Check if rm succeeded
        if _info "$rmResult" | grep -Eq 'record:txt/.*:.*/default'; then
               _info "Successfully deleted $objRef"
               return 0
        else
            _info "Error occurred during txt record delete"
            _info  $rmResult
            _err $rmResult
            return 1
        fi
else
  _info "Record to delete didn't match an existing record"
  _info $result
  _err $result
   return 1
fi
}

####################  Private functions below ##################################
