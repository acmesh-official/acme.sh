#!/usr/bin/env sh

#Here is a script to deploy cert to a Kemp Loadmaster.

#returns 0 means success, otherwise error.

#DEPLOY_KEMP_TOKEN="token"
#DEPLOY_KEMP_URL="https://kemplm.example.com"

########  Public functions #####################

#domain keyfile certfile cafile fullchain
kemplm_deploy() {
  _domain="$1"
  _key_file="$2"
  _cert_file="$3"
  _ca_file="$4"
  _fullchain_file="$5"

  _debug _domain "$_domain"
  _debug _key_file "$_key_file"
  _debug _cert_file "$_cert_file"
  _debug _ca_file "$_ca_file"
  _debug _fullchain_file "$_fullchain_file"

  if ! _exists jq; then
    _err "jq not found"
    return 1
  fi

  # Rename wildcard certs, kemp accepts only alphanumeric names so we delete '*.' from filename
  _kemp_domain=$(echo "${_domain}" | sed 's/\*\.//')
  _debug _kemp_domain "$_kemp_domain"

  # Read config from saved values or env
  _getdeployconf DEPLOY_KEMP_TOKEN
  _getdeployconf DEPLOY_KEMP_URL

  _debug DEPLOY_KEMP_URL "$DEPLOY_KEMP_URL"
  _secure_debug DEPLOY_KEMP_TOKEN "$DEPLOY_KEMP_TOKEN"

  if [ -z "$DEPLOY_KEMP_TOKEN" ]; then
    _err "Kemp Loadmaster token is not found, please define DEPLOY_KEMP_TOKEN."
    return 1
  fi
  if [ -z "$DEPLOY_KEMP_URL" ]; then
    _err "Kemp Loadmaster URL is not found, please define DEPLOY_KEMP_URL."
    return 1
  fi

  # Save current values
  _savedeployconf DEPLOY_KEMP_TOKEN "$DEPLOY_KEMP_TOKEN"
  _savedeployconf DEPLOY_KEMP_URL "$DEPLOY_KEMP_URL"

  # Check if certificate is already installed
  _info "Check if certificate is already present"
  _list_request="{\"cmd\": \"listcert\", \"apikey\": \"${DEPLOY_KEMP_TOKEN}\"}"
  _debug3 _list_request "${_list_request}"
  _kemp_cert_count=$(HTTPS_INSECURE=1 _post "${_list_request}" "${DEPLOY_KEMP_URL}/accessv2" | jq -r '.cert[] | .name' | grep -c "${_kemp_domain}")
  _debug2 _kemp_cert_count "${_kemp_cert_count}"

  _kemp_replace_cert=1
  if [ "${_kemp_cert_count}" -eq 0 ]; then
    _kemp_replace_cert=0
    _info "Certificate does not exist on Kemp Loadmaster"
  else
    _info "Certificate already exists on Kemp Loadmaster"
  fi
  _debug _kemp_replace_cert "${_kemp_replace_cert}"

  # Upload new certificate to Kemp Loadmaster
  _kemp_upload_cert=$(_mktemp)
  cat "${_fullchain_file}" "${_key_file}" | base64 | tr -d '\n' >"${_kemp_upload_cert}"

  _info "Uploading certificate to Kemp Loadmaster"
  _add_data=$(cat "${_kemp_upload_cert}")
  _add_request="{\"cmd\": \"addcert\", \"apikey\": \"${DEPLOY_KEMP_TOKEN}\", \"replace\": ${_kemp_replace_cert}, \"cert\": \"${_kemp_domain}\", \"data\": \"${_add_data}\"}"
  _debug3 _add_request "${_add_request}"
  _kemp_post_result=$(HTTPS_INSECURE=1 _post "${_add_request}" "${DEPLOY_KEMP_URL}/accessv2")
  _retval=$?
  _debug2 _kemp_post_result "${_kemp_post_result}"
  if [ "${_retval}" -eq 0 ]; then
    _kemp_post_status=$(echo "${_kemp_post_result}" | jq -r '.status')
    _kemp_post_message=$(echo "${_kemp_post_result}" | jq -r '.message')
    if [ "${_kemp_post_status}" = "ok" ]; then
      _info "Upload successful"
    else
      _err "Upload failed: ${_kemp_post_message}"
    fi
  else
    _err "Upload failed"
    _retval=1
  fi

  rm "${_kemp_upload_cert}"

  return $_retval
}
