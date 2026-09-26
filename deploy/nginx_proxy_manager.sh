#!/usr/bin/env sh

# Deploy hook to deploy certificate and key to nginx proxy manager/NPMPlus using
# REST API. Separately uploading the intermediate for nginx proxy manager is
# not necessary as the "fullchain" is always used for the certificate.
#
# Environment variables:
#
# DEPLOY_NPM_HOST       - example.com, 192.168.1.1, etc. (REQUIRED)
#                         Host/IP address of NPM admin panel
# DEPLOY_NPM_PORT       - 80, 443, 8443, etc. (REQUIRED)
#                         Port number of NPM admin panel
# DEPLOY_NPM_PROTOCOL   - http/https (REQUIRED)
#                         Protocol to connect to NPM admin panel. https is
#                         STRONGLY recommended
# DEPLOY_NPM_CERTNUM    - 1, 2, 3, etc. (OPTIONAL)
#                         the ID number of the custom certificate to overwrite.
#                         Find it in the NPM admin panel under certificates.
#                         Must already exist.
# DEPLOY_NPM_USER       - admin, npmuser, etc. (REQUIRED)
#                         Authorized user for NPM. Must have permission
#                         to manage certificates.
# DEPLOY_NPM_PASSWORD   - mysecurepassword, mysecretpass, etc. (REQUIRED)
#                         Authorized user's password for NPM 2FA is not supported
#                         since neither nginx proxy manager nor NPMplus support
#                         permanent API tokens. Either disable 2FA for the
#                         administrator account, or (better option) create a new user
#                         with 2FA disabled, and grant this user permissions for
#                         managing certificates.
# DEPLOY_NPM_CERTNAME     My Custom Certificate, Cool Certificate Name, etc. (OPTIONAL)
#                         Name of custom certificate to create. This is only used
#                         to create a certificate the first time. It is IGNORED
#                         once DEPLOY_NPM_CERTNUM is set. If neither certificate
#                         ID number and name are provided, a default name of
#                         "acme.sh custom certificate" with a timestamp suffix will be
#                         used
#
########  Public functions #####################

#domain keyfile certfile cafile fullchain
nginx_proxy_manager_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"
  _cpfx="$6"

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"
  _debug _cpfx "$_cpfx"

  _getdeployconf DEPLOY_NPM_HOST
  _getdeployconf DEPLOY_NPM_PORT
  _getdeployconf DEPLOY_NPM_PROTOCOL
  _getdeployconf DEPLOY_NPM_CERTNUM
  _getdeployconf DEPLOY_NPM_USER
  _getdeployconf DEPLOY_NPM_PASSWORD
  _getdeployconf DEPLOY_NPM_CERTNAME

  if [ -z "$DEPLOY_NPM_HOST" ]; then
    _err "DEPLOY_NPM_HOST must be defined"
    return 1
  fi
  if [ -z "$DEPLOY_NPM_PORT" ]; then
    _err "DEPLOY_NPM_PORT must be defined"
    return 1
  fi
  if [ -z "$DEPLOY_NPM_CERTNUM" ]; then
    _info "DEPLOY_NPM_CERTNUM not provided, a new certificate will be created."
    if [ -z "$DEPLOY_NPM_CERTNAME" ]; then
      DEPLOY_NPM_CERTNAME="acme.sh custom certificate - $(date +'%Y-%m-%d_%H-%M-%S')"
      _info "DEPLOY_NPM_CERTNAME not set. Using default:"
      _info DEPLOY_NPM_CERTNAME "$DEPLOY_NPM_CERTNAME"
    fi
  fi
  if [ "$DEPLOY_NPM_PROTOCOL" != "https" ] && [ "$DEPLOY_NPM_PROTOCOL" != "http" ]; then
    _err "DEPLOY_NPM_PROTOCOL must be either http or https"
    return 1
  fi
  if [ -z "$DEPLOY_NPM_USER" ]; then
    _err "DEPLOY_NPM_USER must be defined"
    return 1
  fi
  if [ -z "$DEPLOY_NPM_PASSWORD" ]; then
    _err "DEPLOY_NPM_PASSWORD must be defined"
    return 1
  fi

  _npm_response_code() {
    _npm_code="$(_egrep_o <"$HTTP_HEADER" "^HTTP[^ ]* .*$" | cut -d " " -f 2-100 | tr -d "\f\n")"
    printf '%s\n' "$_npm_code" | _egrep_o "^[0-9][0-9]*"
  }

  _debug DEPLOY_NPM_USER "$DEPLOY_NPM_USER"
  _secure_debug DEPLOY_NPM_PASSWORD "$DEPLOY_NPM_PASSWORD"
  _npm_user_json=$(printf '%s' "$DEPLOY_NPM_USER" | _json_encode)
  _npm_user_json="${_npm_user_json%\\n}"
  _npm_password_json="$(printf "%s\n" "$DEPLOY_NPM_PASSWORD" | sed 's/\\/\\\\/g;')"
  _npm_password_json=$(printf '%s' "$_npm_password_json" | _json_encode)
  _npm_password_json="${_npm_password_json%\\n}"
  _debug _npm_user_json "$_npm_user_json"
  _secure_debug _npm_password_json "$_npm_password_json"

  _info "Authenticating and fetching temporary API token"
  _npm_token_raw=$(_post '{"identity":"'"$_npm_user_json"'","secret":"'"$_npm_password_json"'"}' "$DEPLOY_NPM_PROTOCOL://$DEPLOY_NPM_HOST:$DEPLOY_NPM_PORT/api/tokens" "" "POST" "application/json")
  _secure_debug _npm_token_raw "$_npm_token_raw"
  _npm_twofactor=$(printf '%s' "$_npm_token_raw" | _egrep_o '("requires_2fa"|"requiresTotp")[[:space:]]*:[[:space:]]*[^,}]*' | cut -d : -f 2 | tr -d ' ')
  if [ "$_npm_twofactor" = "true" ]; then
    _err "2FA is enabled, deployment is not supported. Please disable 2FA or create a new user without 2FA enabled and update your configuration."
    return 1
  fi

  _npm_token_code=$(_npm_response_code)
  _debug _npm_token_code "$_npm_token_code"
  if [ "$_npm_token_code" != "200" ]; then
    _err "Failed to retrieve a token, server response code: $_npm_token_code"
    return 1
  fi

  # first look for a token in JSON
  _npm_type="Nginx Proxy Manager API"
  _npm_token=$(printf '%s' "$_npm_token_raw" | _egrep_o '"token"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d '"' -f 4)
  if [ "$_npm_token" = "" ]; then
    _debug "Token not found in JSON (nginx proxy manager API), checking HTTP header"
    #  look for a token in the header
    _npm_type="NPMplus API"
    _npm_token=$(grep <"$HTTP_HEADER" -i "^Set-Cookie: *__Host-Http-token=" | _tail_n 1 | _egrep_o "__Host-Http-token=[^;]*" | _head_n 1 | cut -d'=' -f2-)
    if [ "$_npm_token" = "" ]; then
      _err "Token not found in HTTP header (NPMplus API). Unable to obtain a token."
      return 1
    fi
  fi
  _info "Detected API type: $_npm_type"
  _secure_debug _npm_token "$_npm_token"
  _info "API token retrieved."

  if [ "$_npm_type" = "Nginx Proxy Manager API" ]; then
    _H1="Authorization: Bearer $_npm_token"
  elif [ "$_npm_type" = "NPMplus API" ]; then
    _H1="Cookie: __Host-Http-token=$_npm_token"
  fi
  export _H1
  _secure_debug _H1 "$_H1"

  nl="\0015\0012"

  # Create new certificate if a certificate ID number was not provided
  if [ -z "$DEPLOY_NPM_CERTNUM" ]; then
    _npm_certname_json=$(printf '%s' "$DEPLOY_NPM_CERTNAME" | _json_encode)
    _npm_certname_json="${_npm_certname_json%\\n}"
    _npm_create_result=$(_post '{"provider":"other","nice_name":"'"$_npm_certname_json"'"}' "$DEPLOY_NPM_PROTOCOL://$DEPLOY_NPM_HOST:$DEPLOY_NPM_PORT/api/nginx/certificates" "" "POST" "application/json")
    _debug _npm_create_result "$_npm_create_result"
    _npm_create_code=$(_npm_response_code)
    if [ "$_npm_create_code" != "201" ]; then
      _err "Failed to create new certificate, server response code: $_npm_create_code"
      return 1
    fi
    DEPLOY_NPM_CERTNUM=$(printf '%s' "$_npm_create_result" | _egrep_o '"id"[[:space:]]*:[[:space:]]*[^,}]*' | cut -d : -f 2 | tr -d ' "')
    _info "Created certificate ID number $DEPLOY_NPM_CERTNUM"
  fi

  _info "Uploading certificates into entry $DEPLOY_NPM_CERTNUM"
  _boundary="--------------------------$(_utc_date | tr -d -- '-: ')"
  _payload="--$_boundary${nl}Content-Disposition: form-data; name=\"certificate_key\"; filename=\"$(basename "$_ckey")\"${nl}Content-Type: application/octet-stream${nl}${nl}$(cat "$_ckey")\0012"
  _payload="$_payload${nl}--$_boundary${nl}Content-Disposition: form-data; name=\"certificate\"; filename=\"$(basename "$_cfullchain")\"${nl}Content-Type: application/octet-stream${nl}${nl}$(cat "$_cfullchain")\0012"
  _payload="$_payload${nl}--$_boundary--${nl}"
  _payload="$(printf "%b_" "$_payload")"
  _payload="${_payload%_}"
  _secure_debug _payload "$_payload"
  _npm_upload_result=$(_post "$_payload" "$DEPLOY_NPM_PROTOCOL://$DEPLOY_NPM_HOST:$DEPLOY_NPM_PORT/api/nginx/certificates/$DEPLOY_NPM_CERTNUM/upload" "" "POST" "multipart/form-data; boundary=${_boundary}")
  unset _H1
  _secure_debug _npm_upload_result "$_npm_upload_result"
  _npm_upload_code=$(_npm_response_code)
  _debug _npm_upload_code "$_npm_upload_code"
  case "$_npm_upload_code" in
  "404")
    _err "Failed to upload certificates, server response code: $_npm_upload_code"
    _err "Check that certificate number $DEPLOY_NPM_CERTNUM exists."
    return 1
    ;;
  "200")
    _info "Certificate uploaded successfully"
    ;;
  *)
    _err "Failed to upload certificates, server response code: $_npm_upload_code"
    return 1
    ;;
  esac

  _info "$(__green "Deployed successfully")"
  _savedeployconf DEPLOY_NPM_HOST "$DEPLOY_NPM_HOST"
  _savedeployconf DEPLOY_NPM_PORT "$DEPLOY_NPM_PORT"
  _savedeployconf DEPLOY_NPM_PROTOCOL "$DEPLOY_NPM_PROTOCOL"
  _savedeployconf DEPLOY_NPM_CERTNUM "$DEPLOY_NPM_CERTNUM"
  _savedeployconf DEPLOY_NPM_USER "$DEPLOY_NPM_USER"
  _savedeployconf DEPLOY_NPM_PASSWORD "$DEPLOY_NPM_PASSWORD" "base64"
  return 0
}
