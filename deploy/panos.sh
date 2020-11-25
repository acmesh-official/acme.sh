#!/usr/bin/env sh

# Script to deploy certificates to Palo Alto Networks PANOS via API
# Note PANOS API KEY and IP address needs to be set prior to running.
# The following variables exported from environment will be used.
# If not set then values previously saved in domain.conf file are used.
#
# Firewall admin with superuser and IP address is required.
#
# export PANOS_USER=""  # required
# export PANOS_PASS=""  # required
# export PANOS_HOST=""  # required

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
  fi
  return 0
}

deployer() {
  content=""
  type=$1 # Types are keygen, cert, key, commit
  _debug "**** Deploying $type *****"
  panos_url="https://$_panos_host/api/"
  if [ "$type" = 'keygen' ]; then
    _H1="Content-Type: application/x-www-form-urlencoded"
    content="type=keygen&user=$_panos_user&password=$_panos_pass"
    # content="$content${nl}--$delim${nl}Content-Disposition: form-data; type=\"keygen\"; user=\"$_panos_user\"; password=\"$_panos_pass\"${nl}Content-Type: application/octet-stream${nl}${nl}"
  fi

  if [ "$type" = 'cert' ] || [ "$type" = 'key' ]; then
    #Generate DEIM
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
      content="$content${nl}--$delim${nl}Content-Disposition: form-data; name=\"file\"; filename=\"$(basename "$_ckey")\"${nl}Content-Type: application/octet-stream${nl}${nl}$(cat "$_ckey")"
    fi
    #Close multipart
    content="$content${nl}--$delim--${nl}${nl}"
    #Convert CRLF
    content=$(printf %b "$content")
  fi

  if [ "$type" = 'commit' ]; then
    export _H1="Content-Type: application/x-www-form-urlencoded"
    cmd=$(printf "%s" "<commit><partial><$_panos_user></$_panos_user></partial></commit>" | _url_encode)
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
  _cdomain="$1"
  _ckey="$2"
  _cfullchain="$5"
  # PANOS ENV VAR check
  if [ -z "$PANOS_USER" ] || [ -z "$PANOS_PASS" ] || [ -z "$PANOS_HOST" ]; then
    _debug "No ENV variables found lets check for saved variables"
    _getdeployconf PANOS_USER
    _getdeployconf PANOS_PASS
    _getdeployconf PANOS_HOST
    _panos_user=$PANOS_USER
    _panos_pass=$PANOS_PASS
    _panos_host=$PANOS_HOST
    if [ -z "$_panos_user" ] && [ -z "$_panos_pass" ] && [ -z "$_panos_host" ]; then
      _err "No host, user and pass found.. If this is the first time deploying please set PANOS_HOST, PANOS_USER and PANOS_PASS in environment variables. Delete them after you have succesfully deployed certs."
      return 1
    else
      _debug "Using saved env variables."
    fi
  else
    _debug "Detected ENV variables to be saved to the deploy conf."
    # Encrypt and save user
    _savedeployconf PANOS_USER "$PANOS_USER" 1
    _savedeployconf PANOS_PASS "$PANOS_PASS" 1
    _savedeployconf PANOS_HOST "$PANOS_HOST" 1
    _panos_user="$PANOS_USER"
    _panos_pass="$PANOS_PASS"
    _panos_host="$PANOS_HOST"
  fi
  _debug "Let's use username and pass to generate token."
  if [ -z "$_panos_user" ] || [ -z "$_panos_pass" ] || [ -z "$_panos_host" ]; then
    _err "Please pass username and password and host as env variables PANOS_USER, PANOS_PASS and PANOS_HOST"
    return 1
  else
    _debug "Getting PANOS KEY"
    deployer keygen
    if [ -z "$_panos_key" ]; then
      _err "Missing apikey."
      return 1
    else
      deployer cert
      deployer key
      deployer commit
    fi
  fi
}
