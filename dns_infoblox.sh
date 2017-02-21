
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

if [[ $result =~ record:txt/.*:.*/default ]]; then
  echo "Successfully created the txt record"
  return 0
else 
  echo "Error encountered during record addition"
  echo $result
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
echo $baseurlnObject

result=`curl -k -u $Infoblox_Creds -X GET $baseurlnObject`

if [[ $result =~ record:txt/.*:.*/default ]]; then
    # Extract object ref
    objRef=`grep -Po 'record:txt/.*:.*/default' <<< $result`
    objRmUrl="https://$Infoblox_Server/wapi/v2.2.2/$objRef"
    rmResult=`curl -k -u $Infoblox_Creds -X DELETE $objRmUrl`
    # Check if rm succeeded
	if [[ $rmResult =~ record:txt/.*:.*/default ]]; then
	       echo "Successfully deleted $objRef"
	       return 0
	else 
	    echo "Error occurred during txt record delete"
	    echo  $rmResult
	    _err $rmResult
   	    return 1
	fi
else 
  echo "Record to delete didn't match an existing record"
  echo $result
  _err $result
   return 1
fi

}

####################  Private functions below ##################################
