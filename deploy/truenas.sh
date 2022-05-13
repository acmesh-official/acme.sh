#!/usr/bin/env sh

# Here is a scipt to deploy the cert to your TrueNAS using the REST API.
# https://www.truenas.com/docs/hub/additional-topics/api/rest_api.html
#
# Written by Frank Plass github@f-plass.de
# https://github.com/danb35/deploy-freenas/blob/master/deploy_freenas.py
# Thanks to danb35 for your template!
#
# Following environment variables must be set:
#
# export DEPLOY_TRUENAS_APIKEY="<API_KEY_GENERATED_IN_THE_WEB_UI"
#
# The following environmental variables may be set if you don't like their
# default values:
#
# DEPLOY_TRUENAS_HOSTNAME - defaults to localhost
# DEPLOY_TRUENAS_SCHEME - defaults to http, set alternatively to https
#
#returns 0 means success, otherwise error.

########  Public functions #####################

#domain keyfile certfile cafile fullchain
truenas_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"

  _getdeployconf DEPLOY_TRUENAS_APIKEY

  if [ -z "$DEPLOY_TRUENAS_APIKEY" ]; then
    _err "TrueNAS API key not found, please set the DEPLOY_TRUENAS_APIKEY environment variable."
    return 1
  fi
  _secure_debug2 DEPLOY_TRUENAS_APIKEY "$DEPLOY_TRUENAS_APIKEY"

  # Optional hostname, scheme for TrueNAS
  _getdeployconf DEPLOY_TRUENAS_HOSTNAME
  _getdeployconf DEPLOY_TRUENAS_SCHEME

  # default values for hostname and scheme
  [ -n "${DEPLOY_TRUENAS_HOSTNAME}" ] || DEPLOY_TRUENAS_HOSTNAME="localhost"
  [ -n "${DEPLOY_TRUENAS_SCHEME}" ] || DEPLOY_TRUENAS_SCHEME="http"

  _debug2 DEPLOY_TRUENAS_HOSTNAME "$DEPLOY_TRUENAS_HOSTNAME"
  _debug2 DEPLOY_TRUENAS_SCHEME "$DEPLOY_TRUENAS_SCHEME"

  _api_url="$DEPLOY_TRUENAS_SCHEME://$DEPLOY_TRUENAS_HOSTNAME/api/v2.0"
  _debug _api_url "$_api_url"

  _H1="Authorization: Bearer $DEPLOY_TRUENAS_APIKEY"
  _secure_debug3 _H1 "$_H1"

  _info "Testing Connection TrueNAS"
  _response=$(_get "$_api_url/system/state")
  _info "TrueNAS system state: $_response."

  if [ -z "$_response" ]; then
    _err "Unable to authenticate to $_api_url."
    _err 'Check your connection settings are correct, e.g.'
    _err 'DEPLOY_TRUENAS_HOSTNAME="192.168.x.y" or DEPLOY_TRUENAS_HOSTNAME="truenas.example.com".'
    _err 'DEPLOY_TRUENAS_SCHEME="https" or DEPLOY_TRUENAS_SCHEME="http".'
    _err "Verify your TrueNAS API key is valid and set correctly, e.g. DEPLOY_TRUENAS_APIKEY=xxxx...."
    return 1
  fi

  _savedeployconf DEPLOY_TRUENAS_APIKEY "$DEPLOY_TRUENAS_APIKEY"
  _savedeployconf DEPLOY_TRUENAS_HOSTNAME "$DEPLOY_TRUENAS_HOSTNAME"
  _savedeployconf DEPLOY_TRUENAS_SCHEME "$DEPLOY_TRUENAS_SCHEME"

  _info "Getting current active certificate from TrueNAS"
  _response=$(_get "$_api_url/system/general")
  _active_cert_id=$(echo "$_response" | grep -B2 '"name":' | grep 'id' | tr -d -- '"id: ,')
  _active_cert_name=$(echo "$_response" | grep '"name":' | sed -n 's/.*: "\(.\{1,\}\)",$/\1/p')
  _param_httpsredirect=$(echo "$_response" | grep '"ui_httpsredirect":' | sed -n 's/.*": \(.\{1,\}\),$/\1/p')
  _debug Active_UI_Certificate_ID "$_active_cert_id"
  _debug Active_UI_Certificate_Name "$_active_cert_name"
  _debug Active_UI_http_redirect "$_param_httpsredirect"

  if [ "$DEPLOY_TRUENAS_SCHEME" = "http" ] && [ "$_param_httpsredirect" = "true" ]; then
    _info "HTTP->HTTPS redirection is enabled"
    _info "Setting DEPLOY_TRUENAS_SCHEME to 'https'"
    DEPLOY_TRUENAS_SCHEME="https"
    _api_url="$DEPLOY_TRUENAS_SCHEME://$DEPLOY_TRUENAS_HOSTNAME/api/v2.0"
    _savedeployconf DEPLOY_TRUENAS_SCHEME "$DEPLOY_TRUENAS_SCHEME"
  fi

  _info "Uploading new certificate to TrueNAS"
  _certname="Letsencrypt_$(_utc_date | tr ' ' '_' | tr -d -- ':')"
  _debug3 _certname "$_certname"

  _certData="{\"create_type\": \"CERTIFICATE_CREATE_IMPORTED\", \"name\": \"${_certname}\", \"certificate\": \"$(_json_encode <"$_cfullchain")\", \"privatekey\": \"$(_json_encode <"$_ckey")\"}"
  _add_cert_result="$(_post "$_certData" "$_api_url/certificate" "" "POST" "application/json")"

  _debug3 _add_cert_result "$_add_cert_result"

  _info "Fetching list of installed certificates"
  _cert_list=$(_get "$_api_url/system/general/ui_certificate_choices")
  _cert_id=$(echo "$_cert_list" | grep "$_certname" | sed -n 's/.*"\([0-9]\{1,\}\)".*$/\1/p')

  _debug3 _cert_id "$_cert_id"

  _info "Current activate certificate ID: $_cert_id"
  _activateData="{\"ui_certificate\": \"${_cert_id}\"}"
  _activate_result="$(_post "$_activateData" "$_api_url/system/general" "" "PUT" "application/json")"

  _debug3 _activate_result "$_activate_result"

  _info "Checking if WebDAV certificate is the same as the TrueNAS web UI"
  _webdav_list=$(_get "$_api_url/webdav")
  _webdav_cert_id=$(echo "$_webdav_list" | grep '"certssl":' | tr -d -- '"certsl: ,')

  if [ "$_webdav_cert_id" = "$_active_cert_id" ]; then
    _info "Updating the WebDAV certificate"
    _debug _webdav_cert_id "$_webdav_cert_id"
    _webdav_data="{\"certssl\": \"${_cert_id}\"}"
    _activate_webdav_cert="$(_post "$_webdav_data" "$_api_url/webdav" "" "PUT" "application/json")"
    _webdav_new_cert_id=$(echo "$_activate_webdav_cert" | _json_decode | grep '"certssl":' | sed -n 's/.*: \([0-9]\{1,\}\),\{0,1\}$/\1/p')
    if [ "$_webdav_new_cert_id" -eq "$_cert_id" ]; then
      _info "WebDAV certificate updated successfully"
    else
      _err "Unable to set WebDAV certificate"
      _debug3 _activate_webdav_cert "$_activate_webdav_cert"
      _debug3 _webdav_new_cert_id "$_webdav_new_cert_id"
      return 1
    fi
    _debug3 _webdav_new_cert_id "$_webdav_new_cert_id"
  else
    _info "WebDAV certificate is not configured or is not the same as TrueNAS web UI"
  fi

  _info "Checking if FTP certificate is the same as the TrueNAS web UI"
  _ftp_list=$(_get "$_api_url/ftp")
  _ftp_cert_id=$(echo "$_ftp_list" | grep '"ssltls_certificate":' | tr -d -- '"certislfa:_ ,')

  if [ "$_ftp_cert_id" = "$_active_cert_id" ]; then
    _info "Updating the FTP certificate"
    _debug _ftp_cert_id "$_ftp_cert_id"
    _ftp_data="{\"ssltls_certificate\": \"${_cert_id}\"}"
    _activate_ftp_cert="$(_post "$_ftp_data" "$_api_url/ftp" "" "PUT" "application/json")"
    _ftp_new_cert_id=$(echo "$_activate_ftp_cert" | _json_decode | grep '"ssltls_certificate":' | sed -n 's/.*: \([0-9]\{1,\}\),\{0,1\}$/\1/p')
    if [ "$_ftp_new_cert_id" -eq "$_cert_id" ]; then
      _info "FTP certificate updated successfully"
    else
      _err "Unable to set FTP certificate"
      _debug3 _activate_ftp_cert "$_activate_ftp_cert"
      _debug3 _ftp_new_cert_id "$_ftp_new_cert_id"
      return 1
    fi
    _debug3 _activate_ftp_cert "$_activate_ftp_cert"
  else
    _info "FTP certificate is not configured or is not the same as TrueNAS web UI"
  fi

  _info "Checking if S3 certificate is the same as the TrueNAS web UI"
  _s3_list=$(_get "$_api_url/s3")
  _s3_cert_id=$(echo "$_s3_list" | grep '"certificate":' | tr -d -- '"certifa:_ ,')

  if [ "$_s3_cert_id" = "$_active_cert_id" ]; then
    _info "Updating the S3 certificate"
    _debug _s3_cert_id "$_s3_cert_id"
    _s3_data="{\"certificate\": \"${_cert_id}\"}"
    _activate_s3_cert="$(_post "$_s3_data" "$_api_url/s3" "" "PUT" "application/json")"
    _s3_new_cert_id=$(echo "$_activate_s3_cert" | _json_decode | grep '"certificate":' | sed -n 's/.*: \([0-9]\{1,\}\),\{0,1\}$/\1/p')
    if [ "$_s3_new_cert_id" -eq "$_cert_id" ]; then
      _info "S3 certificate updated successfully"
    else
      _err "Unable to set S3 certificate"
      _debug3 _activate_s3_cert "$_activate_s3_cert"
      _debug3 _s3_new_cert_id "$_s3_new_cert_id"
      return 1
    fi
    _debug3 _activate_s3_cert "$_activate_s3_cert"
  else
    _info "S3 certificate is not configured or is not the same as TrueNAS web UI"
  fi

  _info "Deleting old certificate"
  _delete_result="$(_post "" "$_api_url/certificate/id/$_active_cert_id" "" "DELETE" "application/json")"

  _debug3 _delete_result "$_delete_result"

  _info "Reloading TrueNAS web UI"
  _restart_UI=$(_get "$_api_url/system/general/ui_restart")
  _debug2 _restart_UI "$_restart_UI"

  if [ -n "$_add_cert_result" ] && [ -n "$_activate_result" ]; then
    return 0
  else
    _err "Certificate update was not succesful, please try again with --debug"
    return 1
  fi
}
