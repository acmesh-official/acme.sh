#!/usr/bin/env sh

http_local_info='Local filesystem HTTP-01 validation plugin
Site: Local filesystem
Docs: github.com/acmesh-official/acme.sh/wiki/HTTP-API
Options:
 HTTP_LOCAL_DIR Directory to copy challenge to
 HTTP_LOCAL_MKDIR Create directory if it doesnt exist (true/false)
 HTTP_LOCAL_VERIFY Verify challenge file is accessible via HTTPS (true/false, default: false)
'

#Here we implement local filesystem-based http validation

#Returns 0 means success, otherwise error.

########  Public functions #####################

#Usage: http_local_deploy domain token keyauthorization
http_local_deploy() {
  _cdomain="$1"
  _ctoken="$2"
  _ckey="$3"

  _debug _cdomain "$_cdomain"
  _debug _ctoken "$_ctoken"

  _getconfig
  if [ "$?" != "0" ]; then
    return 1
  fi

  _info "Deploying challenge file to local directory"
  _wellknown_path="$HTTP_LOCAL_DIR/.well-known/acme-challenge"

  # Create directory if needed
  if [ "$HTTP_LOCAL_MKDIR" = "true" ]; then
    _debug "Creating directory $_wellknown_path"
    mkdir -p "$_wellknown_path"
  fi

  # Create temporary file with token content
  _tempcontent="$(_mktemp)"
  if [ "$?" != "0" ]; then
    _err "Failed to create temporary file"
    return 1
  fi

  echo "$_ckey" > "$_tempcontent"

  # Copy challenge file
  _info "Copying challenge file"
  if ! cp "$_tempcontent" "$_wellknown_path/$_ctoken"; then
    _err "Failed to copy challenge file"
    rm -f "$_tempcontent"
    return 1
  fi

  rm -f "$_tempcontent"

  # Verify the file is accessible via HTTPS if enabled
  if [ "$HTTP_LOCAL_VERIFY" != "false" ]; then
    _info "Verifying challenge file is accessible via HTTPS"
    _verify_url="https://$_cdomain/.well-known/acme-challenge/$_ctoken"
    _debug "Verifying URL: $_verify_url"

    # Try to access the file with curl, ignoring SSL certificate verification
    if ! curl -k -s -o /dev/null -w "%{http_code}" "$_verify_url" | grep -q "200"; then
      _err "Challenge file is not accessible via HTTPS at $_verify_url"
      return 1
    fi
  else
    _debug "Skipping HTTPS verification as HTTP_LOCAL_VERIFY is set to false"
  fi

  return 0
}

#Usage: http_local_rm domain token
http_local_rm() {
  _cdomain="$1"
  _ctoken="$2"

  _debug _cdomain "$_cdomain"
  _debug _ctoken "$_ctoken"

  _getconfig
  if [ "$?" != "0" ]; then
    return 1
  fi

  _info "Removing challenge file from local directory"
  _wellknown_path="$HTTP_LOCAL_DIR/.well-known/acme-challenge"

  # Remove challenge file
  _info "Removing challenge file"
  if ! rm -f "$_wellknown_path/$_ctoken"; then
    _err "Failed to remove challenge file"
    return 1
  fi

  return 0
}

_getconfig() {
  if [ -z "$HTTP_LOCAL_DIR" ]; then
    _err "HTTP_LOCAL_DIR is not defined"
    return 1
  fi

  if [ -z "$HTTP_LOCAL_MKDIR" ]; then
    HTTP_LOCAL_MKDIR="false"
  fi

  if [ -z "$HTTP_LOCAL_VERIFY" ]; then
    HTTP_LOCAL_VERIFY="false"
  fi

  return 0
}
