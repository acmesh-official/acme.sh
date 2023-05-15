#!/usr/bin/env sh

# Script to deploy certificates to Palo Alto Networks PANOS via API
# Note PANOS API KEY and IP address needs to be set prior to running.
# The following variables exported from environment will be used.
# If not set then values previously saved in domain.conf file are used.
#
# Firewall admin with superuser and IP address is required.
#
# You MUST include the following environment variable when first running
# the sccript (can be deleted afterwards):
#
# REQURED:
#     export PANOS_HOST=""  # required
#
# AND one of the two authenticiation methods:
#
# Method 1: Username & Password  (RECOMMENDED)
#     export PANOS_USER=""
#     export PANOS_PASS=""
#
# Method 2: API KEY
#     export PANOS_KEY=""
#
#
# The Username & Password method will automatically generate a new API key if
# no key is found, or if a saved key has expired or is invalid.

# This function is to parse the XML
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
    status=$(echo "$1" | sed 's/^.*"\([a-z]*\)".*/\1/g')
    message=$(echo "$1" | sed 's/^.*<result>\(.*\)<\/result.*/\1/g')
    if [ "$type" = 'keytest' ] && [ "$status" != "success" ]; then
      _debug "****  API Key has EXPIRED or is INVALID ****"
      unset _panos_key
    fi
  fi
  return 0
}

deployer() {
  content=""
  type=$1 # Types are keytest, keygen, cert, key, commit
  panos_url="https://$_panos_host/api/"

  #Test API Key by performing an empty commit.
  if [ "$type" = 'keytest' ]; then
    _debug "**** Testing saved API Key ****"
    _H1="Content-Type: application/x-www-form-urlencoded"
    content="type=commit&cmd=<commit></commit>&key=$_panos_key"
  fi

  # Generate API Key
  if [ "$type" = 'keygen' ]; then
    _debug "**** Generating new API Key ****"
    _H1="Content-Type: application/x-www-form-urlencoded"
    content="type=keygen&user=$_panos_user&password=$_panos_pass"
    # content="$content${nl}--$delim${nl}Content-Disposition: form-data; type=\"keygen\"; user=\"$_panos_user\"; password=\"$_panos_pass\"${nl}Content-Type: application/octet-stream${nl}${nl}"
  fi

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
    fi
    if [ "$type" = 'key' ]; then
      panos_url="${panos_url}?type=import"
      content="--$delim${nl}Content-Disposition: form-data; name=\"category\"\r\n\r\nprivate-key"
      content="$content${nl}--$delim${nl}Content-Disposition: form-data; name=\"certificate-name\"\r\n\r\n$_cdomain"
      content="$content${nl}--$delim${nl}Content-Disposition: form-data; name=\"key\"\r\n\r\n$_panos_key"
      content="$content${nl}--$delim${nl}Content-Disposition: form-data; name=\"format\"\r\n\r\npem"
      content="$content${nl}--$delim${nl}Content-Disposition: form-data; name=\"passphrase\"\r\n\r\n123456"
      content="$content${nl}--$delim${nl}Content-Disposition: form-data; name=\"file\"; filename=\"$(basename "$_cdomain.key")\"${nl}Content-Type: application/octet-stream${nl}${nl}$(cat "$_ckey")"
    fi
    #Close multipart
    content="$content${nl}--$delim--${nl}${nl}"
    #Convert CRLF
    content=$(printf %b "$content")
  fi

  if [ "$type" = 'commit' ]; then
    _debug "**** Committing changes ****"
    export _H1="Content-Type: application/x-www-form-urlencoded"
    if [ "$_panos_user" ]; then
      _commit_desc=$_panos_user
    else
      _commit_desc="acmesh"
    fi
    cmd=$(printf "%s" "<commit><partial><$_commit_desc></$_commit_desc></partial></commit>" | _url_encode)
    content="type=commit&key=$_panos_key&cmd=$cmd"
  fi
  response=$(_post "$content" "$panos_url" "" "POST")
  parse_response "$response" "$type"
  # Saving response to variables
  response_status=$status
  #DEBUG
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
  # VALID ECC KEY CHECK
  keysuffix=$(printf '%s' "$_ckey" | tail -c 8)
  if [ "$keysuffix" = "_ecc.key" ] && [ ! -f "$_ckey" ]; then
    _debug "The ECC key $_ckey doesn't exist. Attempting to strip '_ecc' from the key name"
    _ckey=$(echo "$_ckey" | sed 's/\(.*\)_ecc.key$/\1.key/g')
    if [ ! -f "$_ckey" ]; then
      _err "Unable to find a valid key.  Try issuing the certificate using RSA (non-ECC) encryption."
      return 1
    fi
  fi

  # Environment Checks

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

  # PANOS_KEY
  if [ "$PANOS_PASS" ]; then
    _debug "Detected ENV variable PANOS_PASS. Saving to file."
    _savedeployconf PANOS_PASS "$PANOS_PASS" 1
  else
    _debug "Attempting to load variable PANOS_PASS from file."
    _getdeployconf PANOS_PASS
  fi

  # PANOS_KEY
  if [ "$PANOS_KEY" ]; then
    _debug "Detected ENV variable PANOS_KEY. Saving to file."
    _savedeployconf PANOS_KEY "$PANOS_KEY" 1
  else
    _debug "Attempting to load variable PANOS_KEY from file."
    _getdeployconf PANOS_KEY
  fi

  #Store variables
  _panos_host=$PANOS_HOST
  _panos_key=$PANOS_KEY
  _panos_user=$PANOS_USER
  _panos_pass=$PANOS_PASS

  #Test API Key if found.  If the key is invalid, the variable panos_key will be unset.
  if [ "$_panos_host" ] && [ "$_panos_key" ]; then
    _debug "**** Testing API KEY ****"
    deployer keytest
  fi

  # Check for valid variables
  if [ -z "$_panos_host" ]; then
    _err "No host found.  Please enter a valid host as environment variable PANOS_HOST."
    return 1
  elif [ -z "$_panos_key" ] && { [ -z "$_panos_user" ] || [ -z "$_panos_pass" ]; }; then
    _err "No user and pass OR valid API key found.. If this is the first time deploying please set PANOS_USER and PANOS_PASS -- AND/OR -- PANOS_KEY in environment variables. Delete them after you have succesfully deployed certs."
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
      _err "Unable to generate an API key.  The user and pass may be invalid or not authorized to generate a new key.  Please check the credentials and try again"
      return 1
    else
      deployer cert
      deployer key
      deployer commit
    fi
  fi
}
