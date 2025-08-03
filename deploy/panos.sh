#!/usr/bin/env sh

# Script to deploy certificates to Palo Alto Networks PANOS via API
# Note PANOS API KEY and IP address needs to be set prior to running.
# The following variables exported from environment will be used.
# If not set then values previously saved in domain.conf file are used.
#
# Firewall admin with superuser and IP address is required.
#
# REQURED:
#     export PANOS_HOST=""
#     export PANOS_USER=""    #User *MUST* have Commit and Import Permissions in XML API for Admin Role
#     export PANOS_PASS=""
#
# OPTIONAL
#    export PANOS_TEMPLATE="" #Template Name of panorama managed devices
#
# The script will automatically generate a new API key if
# no key is found, or if a saved key has expired or is invalid.

# This function is to parse the XML response from the firewall
parse_response() {
  type=$2
  if [ "$type" = 'keygen' ]; then
    status=$(echo "$1" | sed 's/^.*\(['\'']\)\([a-z]*\)'\''.*/\2/g')
    if [ "$status" = "success" ]; then
      panos_key=$(echo "$1" | sed 's/^.*\(<key>\)\(.*\)<\/key>.*/\2/g')
      _panos_key=$panos_key
    else
      message="PAN-OS Key could not be set."
    fi
  else
    status=$(echo "$1" | tr -d '\n' | sed 's/^.*"\([a-z]*\)".*/\1/g')
    message=$(echo "$1" | tr -d '\n' | sed 's/.*\(<result>\|<msg>\|<line>\)\([^<]*\).*/\2/g')
    _debug "Firewall message:  $message"
    if [ "$type" = 'keytest' ] && [ "$status" != "success" ]; then
      _debug "****  API Key has EXPIRED or is INVALID ****"
      unset _panos_key
    fi
  fi
  return 0
}

#This function is used to deploy to the firewall
deployer() {
  content=""
  type=$1 # Types are keytest, keygen, cert, key, commit
  panos_url="https://$_panos_host/api/"

  #Test API Key by performing a lookup
  if [ "$type" = 'keytest' ]; then
    _debug "**** Testing saved API Key ****"
    _H1="Content-Type: application/x-www-form-urlencoded"
    # Get Version Info to test key
    content="type=version&key=$_panos_key"
    ## Exclude all scopes for the empty commit
    #_exclude_scope="<policy-and-objects>exclude</policy-and-objects><device-and-network>exclude</device-and-network><shared-object>exclude</shared-object>"
    #content="type=commit&action=partial&key=$_panos_key&cmd=<commit><partial>$_exclude_scope<admin><member>acmekeytest</member></admin></partial></commit>"
  fi

  # Generate API Key
  if [ "$type" = 'keygen' ]; then
    _debug "**** Generating new API Key ****"
    _H1="Content-Type: application/x-www-form-urlencoded"
    content="type=keygen&user=$_panos_user&password=$_panos_pass"
    # content="$content${nl}--$delim${nl}Content-Disposition: form-data; type=\"keygen\"; user=\"$_panos_user\"; password=\"$_panos_pass\"${nl}Content-Type: application/octet-stream${nl}${nl}"
  fi

  # Deploy Cert or Key
  if [ "$type" = 'cert' ] || [ "$type" = 'key' ]; then
    _debug "**** Deploying $type ****"
    #Generate DELIM
    delim="-----MultipartDelimiter$(date "+%s%N")"
    nl="\015\012"
    #Set Header
    export _H1="Content-Type: multipart/form-data; boundary=$delim"
    if [ "$type" = 'cert' ]; then
      panos_url="${panos_url}?type=import"
      content="--$delim${nl}Content-Disposition: form-data; name=\"category\"\r\n\r\ncertificate"
      content="$content${nl}--$delim${nl}Content-Disposition: form-data; name=\"certificate-name\"\r\n\r\n$_cdomain"
      content="$content${nl}--$delim${nl}Content-Disposition: form-data; name=\"key\"\r\n\r\n$_panos_key"
      content="$content${nl}--$delim${nl}Content-Disposition: form-data; name=\"format\"\r\n\r\npem"
      content="$content${nl}--$delim${nl}Content-Disposition: form-data; name=\"file\"; filename=\"$(basename "$_cfullchain")\"${nl}Content-Type: application/octet-stream${nl}${nl}$(cat "$_cfullchain")"
      if [ "$_panos_template" ]; then
        content="$content${nl}--$delim${nl}Content-Disposition: form-data; name=\"target-tpl\"\r\n\r\n$_panos_template"
      fi
    fi
    if [ "$type" = 'key' ]; then
      panos_url="${panos_url}?type=import"
      content="--$delim${nl}Content-Disposition: form-data; name=\"category\"\r\n\r\nprivate-key"
      content="$content${nl}--$delim${nl}Content-Disposition: form-data; name=\"certificate-name\"\r\n\r\n$_cdomain"
      content="$content${nl}--$delim${nl}Content-Disposition: form-data; name=\"key\"\r\n\r\n$_panos_key"
      content="$content${nl}--$delim${nl}Content-Disposition: form-data; name=\"format\"\r\n\r\npem"
      content="$content${nl}--$delim${nl}Content-Disposition: form-data; name=\"passphrase\"\r\n\r\n123456"
      content="$content${nl}--$delim${nl}Content-Disposition: form-data; name=\"file\"; filename=\"$(basename "$_cdomain.key")\"${nl}Content-Type: application/octet-stream${nl}${nl}$(cat "$_ckey")"
      if [ "$_panos_template" ]; then
        content="$content${nl}--$delim${nl}Content-Disposition: form-data; name=\"target-tpl\"\r\n\r\n$_panos_template"
      fi
    fi
    #Close multipart
    content="$content${nl}--$delim--${nl}${nl}"
    #Convert CRLF
    content=$(printf %b "$content")
  fi

  # Commit changes
  if [ "$type" = 'commit' ]; then
    _debug "**** Committing changes ****"
    export _H1="Content-Type: application/x-www-form-urlencoded"
    #Check for force commit - will commit ALL uncommited changes to the firewall. Use with caution!
    if [ "$FORCE" ]; then
      _debug "Force switch detected.  Committing ALL changes to the firewall."
      cmd=$(printf "%s" "<commit><partial><force><admin><member>$_panos_user</member></admin></force></partial></commit>" | _url_encode)
    else
      _exclude_scope="<policy-and-objects>exclude</policy-and-objects><device-and-network>exclude</device-and-network>"
      cmd=$(printf "%s" "<commit><partial>$_exclude_scope<admin><member>$_panos_user</member></admin></partial></commit>" | _url_encode)
    fi
    content="type=commit&action=partial&key=$_panos_key&cmd=$cmd"
  fi

  response=$(_post "$content" "$panos_url" "" "POST")
  parse_response "$response" "$type"
  # Saving response to variables
  response_status=$status
  _debug response_status "$response_status"
  if [ "$response_status" = "success" ]; then
    _debug "Successfully deployed $type"
    return 0
  else
    _err "Deploy of type $type failed. Try deploying with --debug to troubleshoot."
    _debug "$message"
    return 1
  fi
}

# This is the main function that will call the other functions to deploy everything.
panos_deploy() {
  _cdomain=$(echo "$1" | sed 's/*/WILDCARD_/g') #Wildcard Safe Filename
  _ckey="$2"
  _cfullchain="$5"

  # VALID FILE CHECK
  if [ ! -f "$_ckey" ] || [ ! -f "$_cfullchain" ]; then
    _err "Unable to find a valid key and/or cert.  If this is an ECDSA/ECC cert, use the --ecc flag when deploying."
    return 1
  fi

  # PANOS_HOST
  if [ "$PANOS_HOST" ]; then
    _debug "Detected ENV variable PANOS_HOST. Saving to file."
    _savedeployconf PANOS_HOST "$PANOS_HOST" 1
  else
    _debug "Attempting to load variable PANOS_HOST from file."
    _getdeployconf PANOS_HOST
  fi

  # PANOS USER
  if [ "$PANOS_USER" ]; then
    _debug "Detected ENV variable PANOS_USER. Saving to file."
    _savedeployconf PANOS_USER "$PANOS_USER" 1
  else
    _debug "Attempting to load variable PANOS_USER from file."
    _getdeployconf PANOS_USER
  fi

  # PANOS_PASS
  if [ "$PANOS_PASS" ]; then
    _debug "Detected ENV variable PANOS_PASS. Saving to file."
    _savedeployconf PANOS_PASS "$PANOS_PASS" 1
  else
    _debug "Attempting to load variable PANOS_PASS from file."
    _getdeployconf PANOS_PASS
  fi

  # PANOS_KEY
  _getdeployconf PANOS_KEY
  if [ "$PANOS_KEY" ]; then
    _debug "Detected saved key."
    _panos_key=$PANOS_KEY
  else
    _debug "No key detected"
    unset _panos_key
  fi

  # PANOS_TEMPLATE
  if [ "$PANOS_TEMPLATE" ]; then
    _debug "Detected ENV variable PANOS_TEMPLATE. Saving to file."
    _savedeployconf PANOS_TEMPLATE "$PANOS_TEMPLATE" 1
  else
    _debug "Attempting to load variable PANOS_TEMPLATE from file."
    _getdeployconf PANOS_TEMPLATE
  fi

  #Store variables
  _panos_host=$PANOS_HOST
  _panos_user=$PANOS_USER
  _panos_pass=$PANOS_PASS
  _panos_template=$PANOS_TEMPLATE

  #Test API Key if found.  If the key is invalid, the variable _panos_key will be unset.
  if [ "$_panos_host" ] && [ "$_panos_key" ]; then
    _debug "**** Testing API KEY ****"
    deployer keytest
  fi

  # Check for valid variables
  if [ -z "$_panos_host" ]; then
    _err "No host found. If this is your first time deploying, please set PANOS_HOST in ENV variables. You can delete it after you have successfully deployed the certs."
    return 1
  elif [ -z "$_panos_user" ]; then
    _err "No user found. If this is your first time deploying, please set PANOS_USER in ENV variables. You can delete it after you have successfully deployed the certs."
    return 1
  elif [ -z "$_panos_pass" ]; then
    _err "No password found. If this is your first time deploying, please set PANOS_PASS in ENV variables. You can delete it after you have successfully deployed the certs."
    return 1
  else
    # Generate a new API key if no valid API key is found
    if [ -z "$_panos_key" ]; then
      _debug "**** Generating new PANOS API KEY ****"
      deployer keygen
      _savedeployconf PANOS_KEY "$_panos_key" 1
    fi

    # Confirm that a valid key was generated
    if [ -z "$_panos_key" ]; then
      _err "Unable to generate an API key.  The user and pass may be invalid or not authorized to generate a new key.  Please check the PANOS_USER and PANOS_PASS credentials and try again"
      return 1
    else
      deployer cert
      deployer key
      deployer commit
    fi
  fi
}
